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

Teammate’s responsibilities:
- Implement the internal logic for each Test-* function (NetworkAdapter, Gateway, DNS, etc.).
- Ensure each Test-* returns an object with TestName, Success, Details, Target, and Timestamp.
- Implement Write-Log and Export-HtmlReport to handle file outputs.
- Align TestName values with those expected by Invoke-AutoFix (e.g., "DNS", "Gateway", "Web Access").
- Optionally expand Auto-Fix for more detailed diagnostics or adapter restarts.
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
    <#
        TODO (teammate):
        - Implement logging to $Global:LogPath
        - Suggested signature:
          Write-Log -Message "text" -Data $Global:LastResults
    #>
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
     <#
        TODO (teammate): return [pscustomobject] with:
        TestName, Success (bool), Details, Target, Timestamp
        Make sure TestName is "Gateway" for Auto-Fix logic
    #>
}
function Test-ExternalIP {
     <#
        TODO (teammate): return [pscustomobject] with:
        TestName, Success (bool), Details, Target, Timestamp
        Make sure TestName is "External IP" for Auto-Fix logic
    #>
}
function Test-DnsResolution {
    #the parameter was added to make sure the function doesn't crash when called
    param(
        [string]$Domain
    )
     <#
        TODO (teammate): return [pscustomobject] with:
        TestName, Success (bool), Details, Target, Timestamp
        Make sure TestName is "DNS" for Auto-Fix logic
    #>
}
function Test-WebAccess {
    #the parameter was added to make sure the function doesn't crash when called
    param(
        [string]$Url
    )
     <#
        TODO (teammate): return [pscustomobject] with:
        TestName, Success (bool), Details, Target, Timestamp
        Make sure TestName is "Web Access" for Auto-Fix logic
    #>
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
    param(
        [array]$Results
    )
     <#
        TODO (teammate):
        - Convert $Results to HTML and save to $Global:ReportPath
        - Optionally allow custom path
    #>
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
