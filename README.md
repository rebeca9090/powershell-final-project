# Network Diagnostic & Auto-Fix Tool (PowerShell)

## 🧭 Overview
This PowerShell-based **network connectivity diagnostic tool** helps identify and fix common connectivity problems in Windows environments. It automates checks for adapter, gateway, DNS, and web connectivity, then offers safe automated fixes.

The script:
- Runs structured network tests.
- Logs all activity.
- Generates HTML reports.
- Offers an optional Auto-Fix for common issues.

---

## ⚙️ Features
- **Menu-driven interface** with 5 options:
  1. Full Network Test
  2. Basic Connectivity Test
  3. Run Auto-Fix on Last Results
  4. Export HTML Report
  5. Exit
- Modular test functions:
  - `Test-NetworkAdapter`
  - `Test-Gateway`
  - `Test-ExternalIP`
  - `Test-DnsResolution`
  - `Test-WebAccess`
- **Auto-Fix** repairs DNS cache, renews IPs, and suggests adapter resets.
- **Logging system** saves results in timestamped files.
- **HTML reports** include a summary and formatted test results.

---

## 💻 Requirements
- Windows 10 or later
- PowerShell 5.x or 7+
- Internet access (for external IP / web checks)
- Some repairs require **Administrator** privileges

---

## 📂 Project Structure
```
NetworkTool.ps1   # Main script
Logs\             # Log files (auto-created)
Reports\          # HTML reports (auto-created)
README.md         # Documentation
```

The script creates the `Logs` and `Reports` directories automatically if missing.

---

## 🚀 How to Run
1. **Open PowerShell**
2. **Navigate to the folder:**
   ```
   cd "C:\Path\To\Project"
   ```
3. **Allow script execution (Yes to all):**
   ```
   Set-ExecutionPolicy -Scope Process -ExecutionPolicy Bypass
   ```
4. **Run the script:**
   ```
   .\NetworkTool.ps1
   ```
5. The interactive menu will appear.

---

## 🧠 Script Logic & Flow

### 1. Initialization
- Creates log/report directories.
- Defines `$Global:LogPath`, `$Global:ReportPath`, `$Global:LastResults`.

### 2. Menu Loop
- Displays menu options in a loop using `$running = $true`.
- Reads user input and uses a `switch` statement to route actions.

### 3. Full & Basic Tests
- `Run-FullTest` runs adapter, gateway, external IP, DNS, and web tests.
- `Run-BasicTest` runs gateway, external IP, and DNS tests only.
- Each `Test-*`:
  - Runs a connectivity check inside `try/catch`.
  - Returns an object with:
    - `TestName`, `Success`, `Details`, `Target`, `Timestamp`
  - Logs results and adds them to `$Global:LastResults`.
- Prints results in a formatted table.
- Displays pass/fail summary.

### 4. Auto-Fix
- Checks `$Global:LastResults` for failed tests.
- If DNS/Web failed → flushes and re-registers DNS.
- If Gateway/External/Web failed → releases and renews IP.
- If Adapter failed → suggests restarting it.
- Logs actions and prompts user to retest.

### 5. Report Export
- `Export-HtmlReport` builds an HTML file showing summary + table of tests.
- Adds simple CSS for readability.
- Saves file to `Reports\NetReport_YYYYMMDD_HHMMSS.html`.

### 6. Exit
- Ends the loop cleanly with `$running = $false`.

---

## 🧾 Menu Options Explained

**1️⃣ Full Network Test**
- Runs all 5 major tests.
- Displays table of results + summary.
- Prompts to run Auto-Fix if issues found.

**2️⃣ Basic Connectivity Test**
- Runs gateway, external IP, and DNS tests.
- Quicker troubleshooting.

**3️⃣ Run Auto-Fix**
- Uses `$Global:LastResults` to detect failures.
- Applies DNS/IP repairs.
- Suggests adapter restart.
- Logs activity.

**4️⃣ Export HTML Report**
- Saves current results as styled HTML.
- Includes:
  - Timestamp
  - Summary of pass/fail
  - Detailed table

**5️⃣ Exit**
- Prints “Goodbye” and exits the loop.

---

## 📂 Output Examples

### Log Files
Saved to `Logs\NetDiag_YYYYMMDD_HHMMSS.txt`
Each line includes:
- Timestamp
- Log Level (Info/Warning/Error)
- Message

### HTML Reports
Saved to `Reports\NetReport_YYYYMMDD_HHMMSS.html`
Includes:
- Timestamp
- Pass/Fail summary
- Full results table

---

## 🔮 Future Improvements (If Given More Time)
- **Automated Adapter Reset:** Add scripted disable/enable cycle for failed adapters.
- **Improved Gateway Check:** Add HTTP/ARP fallback for ping-blocked networks.
- **Enhanced HTML Styling:** Add color-coded results and charts.
- **Email Integration:** Auto-send reports to admins.
- **Cross-Platform Support:** Make compatible with PowerShell 7 on macOS/Linux.
- **Config File:** Load default settings from JSON/XML.
- **Scheduled Mode:** Allow automatic periodic tests with logging.

---

## 👥 Authors
**Rebeca** – Script architecture, menu system, test orchestration, Auto-Fix, HTML styling, and integration.  
**Phailin** – Internal `Test-*` logic, diagnostic enhancements, and logging integration.

---

📝 *Developed collaboratively in PowerShell and documented with ChatGPT assistance.*
