# Attach Straddle_Grid (FOMC-Only Mode, CLAUDE.md Section 5.1) to a live
# XAUUSD-VIP demo chart ~1 day before a scheduled FOMC date. Run by a
# Windows Scheduled Task - must be robust unattended (retries through
# transient contention, logs everything, never assumes a human is watching).
#
# Does NOT recompile the EA - uses whatever .ex5 is already in the data
# folder's MQL5\Experts\Straddle\. If the source changed since the last
# manual compile, recompile manually before the next scheduled date.

$ErrorActionPreference = "Stop"
$here = Split-Path -Parent $MyInvocation.MyCommand.Path
$logFile = Join-Path $here "tracking.log"
$terminal = "C:\Program Files\MetaTrader 5\terminal64.exe"
$startupIni = Join-Path $here "startup_fomc_live.ini"

function Log($msg) {
    $line = "$(Get-Date -Format 'yyyy-MM-dd HH:mm:ss') [ATTACH] $msg"
    Write-Output $line
    Add-Content -Path $logFile -Value $line
}

Log "=== attach_fomc.ps1 starting ==="

$maxWaitMinutes = 120
$deadline = (Get-Date).AddMinutes($maxWaitMinutes)
while ($true) {
    $running = Get-CimInstance Win32_Process -Filter "Name='terminal64.exe'" |
               Where-Object { $_.ExecutablePath -eq $terminal }
    if (-not $running) { break }
    if ((Get-Date) -gt $deadline) {
        Log "FAILED: terminal still busy after $maxWaitMinutes minutes - giving up. Manual attach needed."
        exit 1
    }
    Log "terminal busy (shared with sibling projects) - waiting 2 min..."
    Start-Sleep -Seconds 120
}

Log "terminal free - launching with FOMC-only startup config"
Start-Process -FilePath $terminal -ArgumentList "/config:`"$startupIni`""
Start-Sleep -Seconds 15

$p = Get-Process terminal64 -ErrorAction SilentlyContinue | Select-Object -First 1
if ($p) {
    Log "SUCCESS: attached (PID $($p.Id)). EA will sit idle until the FOMC window opens (CLAUDE.md Section 5.1 gate 1), then trade the demo account per BasketTP_USD=20/BasketSL_USD=10 if all five gates pass."
} else {
    Log "FAILED: terminal did not appear to start. Manual check needed."
    exit 1
}
