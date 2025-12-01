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

Pending for Rebeca:
- Minor refinements or documentation updates once teammate finishes internal test logic.
- Optional polishing or minor message formatting once all functions are connected.

Phailin's responsibilities:
- Implement the internal logic for each Test-* function (NetworkAdapter, Gateway, DNS, etc.).
- Ensure each Test-* returns an object with TestName, Success, Details, Target, and Timestamp.
- Implement Write-Log and Export-HtmlReport to handle file outputs.
- Align TestName values with those expected by Invoke-AutoFix (e.g., "DNS", "Gateway", "Web Access").
- Optionally expand Auto-Fix for more detailed diagnostics or adapter restarts.

Pending for Phailin:
- Fix network adapter code before adding here
- Add comments to codes to explain the code
- TODO in invoke-AutoFix
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
    [CmdletBinding()]
    param(
        [Parameter(Mandatory = $true)][string]$Message,
        [ValidateSet("Info","Warning","Error")][string]$Level = "Info",
        [array]$Data = $null
    )

    try {
        $timeGenerated = Get-Date -Format "yyyy-MM-dd HH:mm:ss"
        $entry = "{0} [{1}] - {2}" -f $timeGenerated, $Level.ToUpper(), $Message
        Add-Content -Path $Global:LogPath -Value $entry

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
function Test-NetworkAdapter {
     <#
        TODO (teammate): return [pscustomobject] with:
        TestName, Success (bool), Details, Target, Timestamp
        Make sure TestName is "Network Adapter" for Auto-Fix logic
        If you need help understanding anything, reach out or ask ChatGPT
    #>
}
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
            $gateways = $ipconfigs | ForEach-Object { $_.IPv4DefaultGateway.NextHop } | Sort-Object -Unique
            $detailMsgs = @()
            $successList = @()
            foreach ($g in $gateways) {
                $ok = Test-Connection -ComputerName $g -Count 2 -Quiet -ErrorAction SilentlyContinue
                $successList += [PSCustomObject]@{ Gateway=$g; Reachable=$ok }
                $detailMsgs += ("{0} reachable={1}" -f $g, $ok)
            }
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
function Test-ExternalIP {
    [CmdletBinding()] 
    param()

    $ts = Get-Date -Format "yyyy-MM-dd HH:mm:ss"
    $testName = "External IP"

    try {
        $ip = $null
        try { $ip = Invoke-RestMethod -Uri "https://api.ipify.org?format=text" -TimeoutSec 10 } 
        catch { $ip = Invoke-RestMethod -Uri "https://ifconfig.me/ip" -TimeoutSec 10 -ErrorAction SilentlyContinue }

        if (-not $ip) {
            $details = "Unable to retrieve external IP."
            $success = $false
            $target = "External IP"
        }
        else {
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
        $answers = Resolve-DnsName -Name $Domain -ErrorAction SilentlyContinue
        if ($answers) {
            $ips = ($answers | Where-Object { $_.Type -in @('A','AAAA') } | Select-Object -ExpandProperty IPAddress) -join ", "
            $details = if ([string]::IsNullOrWhiteSpace($ips)) { "Resolved non-address records" } else { "Resolved: $ips" }
            $success = $true
            $target = $Domain
        }
        else {
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
        TODO (you & teammate):
        - Use $Global:LastResults to decide what to fix
        - Example actions:
            ipconfig /flushdns
            ipconfig /renew
            netsh int ip reset
    #>
    if (-not $Global:LastResults -or $Global:LastResults.Count -eq 0) {
        Write-Host "No previous test results found. Run a test first." -ForegroundColor Red
        Pause
        return
    }

    #The code below checks for any unsuccessful tests in the last results and stores it in failed results var for further processing
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
    #This is checking for DNS issues and fixing it with flush and register commands
    if ($hasDnsIssue -or $hasWebIssue) {
        Write-Host "Applying DNS repairs (flush and re-register)..." -ForegroundColor Yellow
        ipconfig /flushdns        | Out-Null
        ipconfig /registerdns     | Out-Null
    }
    #This is checking for gateway, external IP or web issues and renewing the IP configuration if any of those are found
    if ($hasGatewayIssue -or $hasExtIpIssue -or $hasWebIssue) {
        Write-Host "Renewing IP configuration..." -ForegroundColor Yellow
        ipconfig /release         | Out-Null
        ipconfig /renew           | Out-Null
    }
    #This is checking for network adapter issues and suggesting a restart of the adapter if found (There is definitely room to improve on this one, like restarting the adapter via script)
    if ($hasAdapterIssue) {
        Write-Host "Adapter issues detected. Consider restarting the adapter." -ForegroundColor Yellow
    }

    Write-Host ""
    Write-Host "Auto-Fix steps completed. Re-run a test to verify connectivity." -ForegroundColor Green

    Write-Log -Message "Auto-Fix executed." -Data $Global:LastResults
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

    $passCount = ($Results | Where-Object { $_.Success }).Count
    $failCount = ($Results | Where-Object { -not $_.Success }).Count
    $generated = Get-Date -Format "yyyy-MM-dd HH:mm:ss"

    $htmlHeader = @"
<html><head><title>Network Report</title></head><body>
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
    $Global:LastResults += Test-NetworkAdapter
    $Global:LastResults += Test-Gateway
    $Global:LastResults += Test-ExternalIP
    $Global:LastResults += Test-DnsResolution -Domain $domain
    $Global:LastResults += Test-WebAccess -Url ("https://{0}" -f $domain)

    #Added below with chatgpt for better user experience, this is dependable on the test functions and that they have TestName, Success and Details properties
    Write-Host "Detailed results:" -ForegroundColor Cyan
    $Global:LastResults | Format-Table TestName, Success, Details -AutoSize
    Write-Host ""

    #This is just showing total of passed and failed tests, the failed tests are important for autofix(first is just storing the var and then write host is what displays it, the vars were created with chatgpt)
    $passCount = ($Global:LastResults | Where-Object { $_.Success }).Count
    $failCount = ($Global:LastResults | Where-Object { -not $_.Success }).Count
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
    $Global:LastResults += Test-Gateway
    $Global:LastResults += Test-ExternalIP
    $Global:LastResults += Test-DnsResolution -Domain $domain

    Write-Host "Detailed results:" -ForegroundColor Cyan
    $Global:LastResults | Format-Table TestName, Success, Details -AutoSize
    Write-Host ""

    $passCount = ($Global:LastResults | Where-Object { $_.Success }).Count
    $failCount = ($Global:LastResults | Where-Object { -not $_.Success }).Count
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
