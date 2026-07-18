# Detach Straddle_Grid (FOMC-Only Mode) ~1 day after a scheduled FOMC date,
# freeing the shared terminal back up for sibling projects. Closes whatever
# terminal64.exe instance is running against our specific install/data
# folder - graceful close first, force-close if it doesn't take (observed
# 2026-07-18/19: CloseMainWindow can silently no-op on this app; needs a
# retry + eventual Stop-Process -Force fallback).

$ErrorActionPreference = "Stop"
$here = Split-Path -Parent $MyInvocation.MyCommand.Path
$logFile = Join-Path $here "tracking.log"
$terminal = "C:\Program Files\MetaTrader 5\terminal64.exe"

function Log($msg) {
    $line = "$(Get-Date -Format 'yyyy-MM-dd HH:mm:ss') [DETACH] $msg"
    Write-Output $line
    Add-Content -Path $logFile -Value $line
}

Log "=== detach_fomc.ps1 starting ==="

$p = Get-CimInstance Win32_Process -Filter "Name='terminal64.exe'" |
     Where-Object { $_.ExecutablePath -eq $terminal } |
     Select-Object -First 1
if (-not $p) {
    Log "no matching terminal running - nothing to detach (already closed, or attach never succeeded)."
    exit 0
}

$proc = Get-Process -Id $p.ProcessId -ErrorAction SilentlyContinue
if ($proc) {
    $null = $proc.CloseMainWindow()
    $proc.WaitForExit(30000)
}

$stillThere = Get-Process -Id $p.ProcessId -ErrorAction SilentlyContinue
if ($stillThere) {
    Log "graceful close did not take after 30s - force-closing PID $($p.ProcessId)"
    Stop-Process -Id $p.ProcessId -Force -ErrorAction SilentlyContinue
    Start-Sleep -Seconds 3
}

$finalCheck = Get-Process -Id $p.ProcessId -ErrorAction SilentlyContinue
if ($finalCheck) {
    Log "FAILED: PID $($p.ProcessId) still running after force-close attempt. Manual check needed."
    exit 1
} else {
    Log "SUCCESS: detached. Terminal free for sibling projects until the next scheduled attach."
}
