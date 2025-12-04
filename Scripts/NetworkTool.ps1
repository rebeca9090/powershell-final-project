<#
.Author        : Rebeca
.Date          : 2025-11-29
.Description   : Handles the main script flow, including menu display, test orchestration, Auto-Fix logic, and report integration.
.Notes (written with chatgpt assistance):
Rebeca’s responsibilities:
- Created all structural functions and global variables for logs, reports, and test results.
- Implemented the main menu loop and user interaction flow.
- Built Run-FullTest and Run-BasicTest to coordinate all individual network test functions.
- Added domain input logic, pass/fail counting, and automatic Auto-Fix prompt handling.
- Integrated Export-HtmlReport and Write-Log calls for future logging/reporting.
- Developed the core logic for Invoke-AutoFix, including detecting failed tests and triggering DNS/IP repairs.

Phailin's responsibilities:
- Implement the internal logic for each Test-* function (NetworkAdapter, Gateway, DNS, etc.).
- Ensure each Test-* returns an object with TestName, Success, Details, Target, and Timestamp.
- Implement Write-Log and Export-HtmlReport to handle file outputs.
- Align TestName values with those expected by Invoke-AutoFix (e.g., "DNS", "Gateway", "Web Access").
- Optionally expand Auto-Fix for more detailed diagnostics or adapter restarts.

Update 2025-12-02 (Rebeca):
- Fixed menu loop to exit cleanly using $running flag.
- Removed duplicate additions to $Global:LastResults in Run-FullTest/Run-BasicTest.
- Improved HTML report styling with basic CSS for readability.
- Added extra logging for individual Auto-Fix steps (DNS and IP repair).
- Wrapped ipconfig calls in try/catch to handle non-admin scenarios and log failures more clearly.
#>

# Initialize global variables that will respectively, store the last test results, the timestamp for log/report files, and the base path of the script
$Global:LastResults = @()
$timestamp = Get-Date -Format "yyyyMMdd_HHmmss"
$basePath = $PSScriptRoot

# Creates/Assures existence of Logs and Reports directories
New-Item -ItemType Directory -Path (Join-Path $basePath "Logs") -Force | Out-Null
New-Item -ItemType Directory -Path (Join-Path $basePath "Reports") -Force | Out-Null

# Global paths for log and HTML report
$Global:LogPath    = Join-Path $basePath ("Logs\NetDiag_{0}.txt"  -f $timestamp)
$Global:ReportPath = Join-Path $basePath ("Reports\NetReport_{0}.html" -f $timestamp)

function Write-Log {
    # the CmdletBinding allows us to use advanced function features
    [CmdletBinding()]
    param(
        [Parameter(Mandatory = $true)]
        [string]$Message,
        
        [ValidateSet("Info","Warning","Error")]
        [string]$Level = "Info",
        
        [array]$Data = $null
    )

    try {
        # Create formatted log entry with timestamp and level
        $timeGenerated = Get-Date -Format "yyyy-MM-dd HH:mm:ss"
        $entry = "{0} [{1}] - {2}" -f $timeGenerated, $Level.ToUpper(), $Message
        
        # Append to the log file
        Add-Content -Path $Global:LogPath -Value $entry

        # Return structured object
        return [PSCustomObject]@{
            Timestamp = $timeGenerated
            Level     = $Level
            Message   = $Message
        }
    }
    catch {
        Write-Warning "Failed to write log: $_"
    }
}

# Check what network adapters are present and in "Up" status
function Test-NetworkAdapter {
    [CmdletBinding()] 
    param()

    $ts = Get-Date -Format "yyyy-MM-dd HH:mm:ss"
    $testName = "Network Adapter"

    try {
        # Getting all network adapters
        $adapters = @(Get-NetAdapter -ErrorAction SilentlyContinue)

        # Check if no network adapters found
        if ($adapters.Count -eq 0) {
            $details = "No network adapters found."
            $success = $false
            $target = "Local adapters"
        }
        else {
            # Find the network adapters that has "Up" status
            $up = @($adapters | Where-Object { $_.Status.Trim() -eq "Up" })
            
            if ($up.Count -gt 0) {
                $names = ($up | ForEach-Object { $_.Name }) -join ", "
                $details = "Up adapters: $names"
                $success = $true
                $target = $names
            } else {
                $list = ($adapters | ForEach-Object { "$($_.Name): $($_.Status)" }) -join "; "
                $details = "No adapters reporting 'Up'. Found: $list"
                $success = $false
                $target = "Local adapters"
            }
        }
    }
    catch {
        $details = "Exception: $_"
        $success = $false
        $target = "Local adapters"
    }
    # Create the structured object for the auto-fix and reporting
    $result = [PSCustomObject]@{
        TestName  = $testName
        Success   = [bool]$success
        Details   = $details
        Target    = $target
        Timestamp = $ts
    }
    # add results to global collection and log the results
    $level = if ($success) { "Info" } else { "Error" }
    Write-Log -Message "Test: $testName - Success: $success - $details" -Level $level -Data @($result)
    $Global:LastResults += $result
    return $result
}
# Check for gateway and test connectivity to the default gateway
# NOTE (Rebeca 2025-12-02):
# The Test-Gateway function may fail on university or corporate networks even when connectivity works,
# because some routers/firewalls block ICMP (ping) requests for security.
# This is normal behavior and not an error in the script.
function Test-Gateway {
    [CmdletBinding()] 
    param()

    $ts = Get-Date -Format "yyyy-MM-dd HH:mm:ss"
    $testName = "Gateway"

    try {
        $ipconfigs = Get-NetIPConfiguration -ErrorAction SilentlyContinue | Where-Object { $null -ne $_.IPv4DefaultGateway }
        
        if (-not $ipconfigs) {
            $details = "No IPv4 default gateway configured."
            $success = $false
            $target = "None"
        }
        else {
            # Getting the gateway IP addresses for testing
            $gateways = $ipconfigs | ForEach-Object { $_.IPv4DefaultGateway.NextHop } | Sort-Object -Unique
            $detailMsgs = @()
            $successList = @()
            foreach ($g in $gateways) {
                $ok = Test-Connection -ComputerName $g -Count 2 -Quiet -ErrorAction SilentlyContinue
                $successList += [PSCustomObject]@{ Gateway=$g; Reachable=$ok }
                $detailMsgs += ("{0} reachable={1}" -f $g, $ok)
            }
            # Success only if all gateway are reachable
            $allOk = ($successList | Where-Object { -not $_.Reachable }).Count -eq 0
            $details = $detailMsgs -join "; "
            $success = $allOk
            $target = ($gateways -join ", ")
        }
    }
    catch {
        $details = "Exception: $_"
        $success = $false
        $target = "Gateway lookup"
    }

    $result = [PSCustomObject]@{
        TestName  = $testName
        Success   = [bool]$success
        Details   = $details
        Target    = $target
        Timestamp = $ts
    }

    $level = if ($success) { "Info" } else { "Error" }
    Write-Log -Message "Test: $testName - Success: $success - $details" -Level $level -Data @($result)
    $Global:LastResults += $result
    return $result
}
# Verifying internet connectivity by retrieving public IP address
function Test-ExternalIP {
    [CmdletBinding()] 
    param()

    $ts = Get-Date -Format "yyyy-MM-dd HH:mm:ss"
    $testName = "External IP"

    try {
        # Testing with 2 different external IP services
        $ip = $null
        try { $ip = Invoke-RestMethod -Uri "https://api.ipify.org?format=text" -TimeoutSec 10 } 
        catch { $ip = Invoke-RestMethod -Uri "https://ifconfig.me/ip" -TimeoutSec 10 -ErrorAction SilentlyContinue }

        # If both try-catch fails, tells us theres no internet connectivity
        if (-not $ip) {
            $details = "Unable to retrieve external IP."
            $success = $false
            $target = "External IP"
        }
        else {
            # when retrieving public Ip is successful
            $details = "External IP: $ip"
            $success = $true
            $target = $ip
        }
    }
    catch {
        $details = "Exception: $_"
        $success = $false
        $target = "External IP lookup"
    }

    $result = [PSCustomObject]@{
        TestName  = $testName
        Success   = [bool]$success
        Details   = $details
        Target    = $target
        Timestamp = $ts
    }

    $level = if ($success) { "Info" } else { "Error" }
    Write-Log -Message "Test: $testName - Success: $success - $details" -Level $level -Data @($result)
    $Global:LastResults += $result
    return $result
}
#Test DNS by resolving domain to IP address
function Test-DnsResolution {
    #the parameter was added to make sure the function doesn't crash when called
    [CmdletBinding()] 
    param(
        [Parameter(Mandatory = $true)]
        [string]$Domain
    )

    $ts = Get-Date -Format "yyyy-MM-dd HH:mm:ss"
    $testName = "DNS"

    try {
        # Testing to resolve domain name to IP address (eg. $Domain = google.com)
        $answers = Resolve-DnsName -Name $Domain -ErrorAction SilentlyContinue

        if ($answers) {
            $ips = ($answers | Where-Object { $_.Type -in @('A','AAAA') } | Select-Object -ExpandProperty IPAddress) -join ", "
            $details = if ([string]::IsNullOrWhiteSpace($ips)) { "Resolved non-address records" } else { "Resolved: $ips" }
            $success = $true
            $target = $Domain
        }
        else {
            # When the DNS resolution completely fails
            $details = "Resolution failed for $Domain."
            $success = $false
            $target = $Domain
        }
    }
    catch {
        $details = "Exception: $_"
        $success = $false
        $target = $Domain
    }

    $result = [PSCustomObject]@{
        TestName  = $testName
        Success   = [bool]$success
        Details   = $details
        Target    = $target
        Timestamp = $ts
    }

    $level = if ($success) { "Info" } else { "Error" }
    Write-Log -Message "Test: $testName - Success: $success - $details" -Level $level -Data @($result)
    $Global:LastResults += $result
    return $result
}
# Testing web connectivity using HTTP/ HTTPS requests (eg. https://google.com)
function Test-WebAccess {
    #the parameter was added to make sure the function doesn't crash when called
    [CmdletBinding()] 
    param(
        [Parameter(Mandatory = $true)]
        [string]$Url
    )

    $ts = Get-Date -Format "yyyy-MM-dd HH:mm:ss"
    $testName = "Web Access"

    try {
        $success = $false
        $details = ""
        $target = $Url

        try {
            $resp = Invoke-WebRequest -Uri $Url -Method Head -TimeoutSec 10 -ErrorAction Stop
            $status = if ($resp.StatusCode) { $resp.StatusCode } else { 200 }
            $details = "HTTP $status (HEAD)"
            $success = ($status -ge 200 -and $status -lt 400)
        } catch {
            try {
                $resp2 = Invoke-WebRequest -Uri $Url -Method Get -TimeoutSec 12 -ErrorAction Stop
                $status2 = if ($resp2.StatusCode) { $resp2.StatusCode } else { 200 }
                $details = "HTTP $status2 (GET)"
                $success = ($status2 -ge 200 -and $status2 -lt 400)
            } catch {
                $details = "Request failed: $($_.Exception.Message)"
                $success = $false
            }
        }
    }
    catch {
        $details = "Exception: $_"
        $success = $false
        $target = $Url
    }

    $result = [PSCustomObject]@{
        TestName  = $testName
        Success   = [bool]$success
        Details   = $details
        Target    = $target
        Timestamp = $ts
    }

    $level = if ($success) { "Info" } else { "Error" }
    Write-Log -Message "Test: $testName - Success: $success - $details" -Level $level -Data @($result)
    $Global:LastResults += $result
    return $result
}
function Invoke-AutoFix {
    <#
        Updated 2025-12-02 (Rebeca):
        - Added detailed logging around each repair step.
        - Wrapped ipconfig calls in try/catch to handle non-admin or other failures gracefully.
    #>

    if (-not $Global:LastResults -or $Global:LastResults.Count -eq 0) {
        Write-Host "No previous test results found. Run a test first." -ForegroundColor Red
        Pause
        return
    }

    # Check for any unsuccessful tests
    $failedTests = $Global:LastResults | Where-Object { -not $_.Success }
    if (-not $failedTests -or $failedTests.Count -eq 0) {
        Write-Host "All tests are currently passing. Nothing to fix." -ForegroundColor Green
        Pause
        return
    }

    Write-Host "Running Auto-Fix based on failed tests..." -ForegroundColor Cyan
    Write-Host ""

    $hasAdapterIssue = $failedTests.TestName -contains "Network Adapter"
    $hasGatewayIssue = $failedTests.TestName -contains "Gateway"
    $hasDnsIssue     = $failedTests.TestName -contains "DNS"
    $hasExtIpIssue   = $failedTests.TestName -contains "External IP"
    $hasWebIssue     = $failedTests.TestName -contains "Web Access"

    # DNS-related fixes (flush + re-register)
    if ($hasDnsIssue -or $hasWebIssue) {
        Write-Host "Applying DNS repairs (flush and re-register)..." -ForegroundColor Yellow
        Write-Log -Message "Starting DNS repair (flushdns + registerdns)." -Level "Info"

        try {
            ipconfig /flushdns    | Out-Null
            ipconfig /registerdns | Out-Null
            Write-Log -Message "DNS repair completed successfully." -Level "Info"
        }
        catch {
            Write-Host "DNS repair failed. You may need to run PowerShell as Administrator." -ForegroundColor Red
            Write-Log -Message "DNS repair failed: $_" -Level "Error"
        }
    }

    # IP configuration fixes (release + renew)
    if ($hasGatewayIssue -or $hasExtIpIssue -or $hasWebIssue) {
        Write-Host "Renewing IP configuration..." -ForegroundColor Yellow
        Write-Log -Message "Starting IP configuration repair (release + renew)." -Level "Info"

        try {
            ipconfig /release | Out-Null
            ipconfig /renew   | Out-Null
            Write-Log -Message "IP configuration repair completed successfully." -Level "Info"
        }
        catch {
            Write-Host "IP configuration repair failed. You may need to run PowerShell as Administrator." -ForegroundColor Red
            Write-Log -Message "IP configuration repair failed: $_" -Level "Error"
        }
    }

    # Adapter issues (still advisory, not automatic restart)
    if ($hasAdapterIssue) {
        Write-Host "Adapter issues detected. Consider restarting the adapter." -ForegroundColor Yellow
        Write-Log -Message "Adapter issues detected; user advised to restart adapter manually." -Level "Warning"
    }

    Write-Host ""
    Write-Host "Auto-Fix steps completed. Re-run a test to verify connectivity." -ForegroundColor Green
    Write-Log -Message "Auto-Fix sequence finished." -Level "Info" -Data $Global:LastResults
    Pause
}

function Export-HtmlReport {
    [CmdletBinding()] 
    param(
        [Parameter(Mandatory = $true)]
        [array]$Results,
        [string]$Path
    )

    if (-not $Results -or $Results.Count -eq 0) { Write-Host "No results to export."; return }

    $outFile = if ($Path) { $Path } else { $Global:ReportPath }

    $passCount = @($Results | Where-Object { $_.Success }).Count
    $failCount = @($Results | Where-Object { -not $_.Success }).Count
    $generated = Get-Date -Format "yyyy-MM-dd HH:mm:ss"

    # Updated 2025-12-02 (Rebeca): added CSS styling and summary section for nicer HTML reports.
    $style = @"
<style>
    body {
        font-family: Segoe UI, Arial, sans-serif;
        margin: 20px;
    }
    h1 {
        color: #2c3e50;
    }
    h2 {
        margin-top: 24px;
        color: #34495e;
    }
    ul {
        list-style-type: disc;
        margin-left: 20px;
    }
    table {
        border-collapse: collapse;
        width: 100%;
        margin-top: 10px;
    }
    th, td {
        border: 1px solid #cccccc;
        padding: 6px 10px;
        text-align: left;
        vertical-align: top;
    }
    th {
        background-color: #f2f2f2;
        font-weight: bold;
    }
</style>
"@
    $htmlHeader = @"
<html><head><title>Network Report</title>$style</head><body>
<h1>Network Report</h1><p>Generated: $generated</p>
<h2>Summary</h2><ul><li>Passed: $passCount</li><li>Failed: $failCount</li></ul>
<h2>Details</h2>
"@

    $tableHtml = $Results | Select-Object TestName, Timestamp, Target, Success, Details | ConvertTo-Html -Fragment -As Table
    $htmlFooter = "</body></html>"

    ($htmlHeader + $tableHtml + $htmlFooter) | Out-File -FilePath $outFile -Encoding UTF8
    Write-Host "Report written to $outFile" -ForegroundColor Green
    Write-Log -Message "Exported HTML report to $outFile" -Level "Info" -Data $Results
}
function Run-FullTest {
    $Global:LastResults = @()
    #Used chatgpt for the logic of domain input
    $domain = Read-Host "Enter a domain for DNS/web tests (press Enter for default: google.com)"
    if ([string]::IsNullOrWhiteSpace($domain)) {
    $domain = "google.com"
    }

    Write-Host "Using domain: $domain" -ForegroundColor Yellow
    Write-Host ""
    Test-NetworkAdapter
    Test-Gateway
    Test-ExternalIP
    Test-DnsResolution -Domain $domain
    Test-WebAccess -Url ("https://{0}" -f $domain)

    #Added below with chatgpt for better user experience, this is dependable on the test functions and that they have TestName, Success and Details properties
    Write-Host "Detailed results:" -ForegroundColor Cyan
    $Global:LastResults | Format-Table TestName, Success, Details -AutoSize
    Write-Host ""

    #This is just showing total of passed and failed tests, the failed tests are important for autofix(first is just storing the var and then write host is what displays it, the vars were created with chatgpt)
    $passCount = @($Global:LastResults | Where-Object { $_.Success }).Count
    $failCount = @($Global:LastResults | Where-Object { -not $_.Success }).Count
    Write-Host "Summary:" -ForegroundColor Cyan
    Write-Host "  Passed: $passCount"
    Write-Host "  Failed: $failCount"

    Write-Log -Message "Full test run completed. Passed: $passCount, Failed: $failCount" -Data $Global:LastResults

    if ($failCount -gt 0) {
        Write-Host ""
        $answer = Read-Host "Issues were detected. Would you like to run Auto-Fix? (Y/N)"

        if ($answer.ToUpper() -eq 'Y') {
            Invoke-AutoFix
        }
        else {
            Write-Host "Skipping Auto-Fix." -ForegroundColor Yellow
            Pause
        }
    }
    else {
        Write-Host ""
        Write-Host "All tests passed. No Auto-Fix needed." -ForegroundColor Green
        Pause
    }
}
function Run-BasicTest{
    #Very similar to Run-FullTest but only runs Gateway, ExternalIP and DNS tests, so code is reused with slight modifications
    $Global:LastResults = @()

    $domain = Read-Host "Enter a domain for DNS/web tests (press Enter for default: google.com)"
    if ([string]::IsNullOrWhiteSpace($domain)) {
        $domain = "google.com"
    }

    Write-Host "Using domain: $domain" -ForegroundColor Yellow
    Write-Host ""
    Test-Gateway
    Test-ExternalIP
    Test-DnsResolution -Domain $domain

    Write-Host "Detailed results:" -ForegroundColor Cyan
    $Global:LastResults | Format-Table TestName, Success, Details -AutoSize
    Write-Host ""

    $passCount = @($Global:LastResults | Where-Object { $_.Success }).Count
    $failCount = @($Global:LastResults | Where-Object { -not $_.Success }).Count
    Write-Host "Summary:" -ForegroundColor Cyan
    Write-Host "  Passed: $passCount"
    Write-Host "  Failed: $failCount"

    Write-Log -Message "Basic test run completed. Passed: $passCount, Failed: $failCount" -Data $Global:LastResults

    if ($failCount -gt 0) {
        Write-Host ""
        $answer = Read-Host "Issues were detected. Would you like to run Auto-Fix? (Y/N)"

        if ($answer.ToUpper() -eq 'Y') {
            Invoke-AutoFix
        }
        else {
            Write-Host "Skipping Auto-Fix." -ForegroundColor Yellow
            Pause
        }
    }
    else {
        Write-Host ""
        Write-Host "All tests passed. No Auto-Fix needed." -ForegroundColor Green
        Pause
    }
}
function Show-Menu {
    Clear-Host
    Write-Host "==============================="
    Write-Host "       NETWORK TOOL MENU       "
    Write-Host "==============================="
    Write-Host "1) Full Network Test"
    Write-Host "2) Basic Connectivity Test"
    Write-Host "3) Run Auto-Fix On Last Results"
    Write-Host "4) Export HTML Report"
    Write-Host "5) Exit"
    Write-Host "==============================="
}
$running = $true
do {
    Show-Menu
    $choice = Read-Host "Select an option, from 1 to 5"

    switch ($choice.ToUpper()) {
        '1' {
            Run-FullTest
        }

        '2' {
            Run-BasicTest
        }

        '3' {
            Invoke-AutoFix
        }
        '4' {
            if (-not $Global:LastResults -or $Global:LastResults.Count -eq 0) {
                Write-Host "No results available. Run a test first." -ForegroundColor Red
                Pause
            }
            else {
            Export-HtmlReport -Results $Global:LastResults
            }
        }

        '5' {
            Write-Host "Exiting NetworkTool. Goodbye!" -ForegroundColor Cyan
            $running = $false   # tell the loop to stop
        }

        Default {
            Write-Host ""
            Write-Host "Invalid choice. Please try again." -ForegroundColor Red
            Start-Sleep -Seconds 1.5
        }
    }

} while ($running)
