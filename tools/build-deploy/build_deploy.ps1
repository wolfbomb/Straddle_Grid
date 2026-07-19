# Compile Straddle_Grid.mq5 and deploy the result into the MT5 data folder
# used for live/manual charts (CLAUDE.md Section 9: MQL5/Experts/Straddle/).
#
# "Deploy" here means: copy the repo's .mq5 source into the data folder's
# MQL5\Experts\Straddle\, then compile it there with MetaEditor so the .ex5
# MT5 actually loads is built from the current repo source — not a stale
# copy left over from a previous manual compile (attach_fomc.ps1 explicitly
# does NOT recompile and depends on this having been done beforehand).
#
# Usage:
#   .\build_deploy.ps1
#   .\build_deploy.ps1 -DataDir "C:\...\Terminal\<hash>"
#   .\build_deploy.ps1 -MetaEditor "C:\Program Files\MetaTrader 5\metaeditor64.exe"
#
# DataDir resolution order: -DataDir param > $env:DATADIR > DATADIR= line in
# tools/strategy-tester/.env.local (same file run_tests.sh reads) > the
# known default for this machine.

param(
    [string]$DataDir,
    [string]$MetaEditor
)

$ErrorActionPreference = "Stop"
$here = Split-Path -Parent $MyInvocation.MyCommand.Path
$repoRoot = Resolve-Path (Join-Path $here "..\..")
$logFile = Join-Path $here "build_deploy.log"

function Log($msg) {
    # Write-Host (not Write-Output) - this is called from inside functions
    # whose return value feeds Join-Path/etc.; Write-Output would leak the
    # log line into that return value as a second pipeline object.
    $line = "$(Get-Date -Format 'yyyy-MM-dd HH:mm:ss') [BUILD] $msg"
    Write-Host $line
    Add-Content -Path $logFile -Value $line
}

function Convert-BashPathToWindows($p) {
    # tools/strategy-tester/.env.local stores DATADIR in Git-Bash form
    # ("/c/Users/...") since run_tests.sh sources it as plain bash.
    if ($p -match '^/([a-zA-Z])/(.*)$') {
        return "$($Matches[1].ToUpper()):\$($Matches[2] -replace '/', '\')"
    }
    return $p
}

function Resolve-DataDir {
    if ($DataDir) { return $DataDir }
    if ($env:DATADIR) { return (Convert-BashPathToWindows $env:DATADIR) }

    $envLocal = Join-Path $repoRoot "tools\strategy-tester\.env.local"
    if (Test-Path $envLocal) {
        $line = Select-String -Path $envLocal -Pattern '^\s*DATADIR\s*=\s*"?([^"]+)"?\s*$' -ErrorAction SilentlyContinue |
                Select-Object -First 1
        if ($line) {
            $raw = $line.Matches[0].Groups[1].Value
            Log "DataDir from tools\strategy-tester\.env.local: $raw"
            return (Convert-BashPathToWindows $raw)
        }
    }

    $fallback = "C:\Users\nimrod.resulta\AppData\Roaming\MetaQuotes\Terminal\D0E8209F77C8CF37AD8BF550E51FF075"
    Log "No -DataDir, `$env:DATADIR, or .env.local entry found - using known default: $fallback"
    return $fallback
}

function Resolve-MetaEditor {
    if ($MetaEditor) { return $MetaEditor }
    if ($env:METAEDITOR) { return $env:METAEDITOR }
    return "C:\Program Files\MetaTrader 5\metaeditor64.exe"
}

Log "=== build_deploy.ps1 starting ==="

$resolvedDataDir = Resolve-DataDir
$resolvedMetaEditor = Resolve-MetaEditor

if (-not (Test-Path $resolvedMetaEditor)) {
    Log "FAILED: MetaEditor not found at '$resolvedMetaEditor'. Pass -MetaEditor <path> or set `$env:METAEDITOR."
    exit 1
}

$srcMq5 = Join-Path $repoRoot "MQL5\Experts\Straddle\Straddle_Grid.mq5"
if (-not (Test-Path $srcMq5)) {
    Log "FAILED: repo source not found at '$srcMq5'."
    exit 1
}

$destDir = Join-Path $resolvedDataDir "MQL5\Experts\Straddle"
$destMq5 = Join-Path $destDir "Straddle_Grid.mq5"

if (-not (Test-Path $resolvedDataDir)) {
    Log "FAILED: data folder not found at '$resolvedDataDir'. Pass -DataDir <path>."
    exit 1
}

$liveTerminal = Get-CimInstance Win32_Process -Filter "Name='terminal64.exe'" -ErrorAction SilentlyContinue |
                Where-Object { $_.CommandLine -and $_.CommandLine -like "*$resolvedDataDir*" }
if ($liveTerminal) {
    Log "WARNING: terminal64.exe appears to be running against this data folder (PID $($liveTerminal.ProcessId)). If Straddle_Grid is attached to a live chart, MetaEditor may fail to overwrite a locked .ex5 - close the chart's EA first if the compile below fails."
}

Log "Deploying source: $srcMq5 -> $destMq5"
New-Item -ItemType Directory -Force -Path $destDir | Out-Null
Copy-Item -Path $srcMq5 -Destination $destMq5 -Force

$compileLog = Join-Path $here "compile.log"
if (Test-Path $compileLog) { Remove-Item $compileLog -Force }

Log "Compiling via MetaEditor..."
$proc = Start-Process -FilePath $resolvedMetaEditor `
    -ArgumentList "/compile:`"$destMq5`"", "/log:`"$compileLog`"" `
    -NoNewWindow -PassThru -Wait
$exitCode = $proc.ExitCode
Log "MetaEditor exit code: $exitCode"

Start-Sleep -Seconds 1  # log file write can lag process exit slightly

if (-not (Test-Path $compileLog)) {
    Log "FAILED: no compile log produced at '$compileLog'."
    exit 1
}

# MetaEditor writes this log UTF-16LE (same as MT5 tester journals).
$compileText = Get-Content -Path $compileLog -Encoding Unicode -Raw
Add-Content -Path $logFile -Value "--- compile.log ---`r`n$compileText--- end compile.log ---"

if ($compileText -match '(\d+)\s+errors?,\s*(\d+)\s+warnings?') {
    $errors = [int]$Matches[1]
    $warnings = [int]$Matches[2]
    if ($errors -eq 0 -and $warnings -eq 0) {
        $destEx5 = Join-Path $destDir "Straddle_Grid.ex5"
        Log "SUCCESS: 0 errors, 0 warnings. Deployed: $destEx5"
        exit 0
    } else {
        Log "FAILED: compile finished with $errors error(s), $warnings warning(s). See $compileLog"
        exit 1
    }
} else {
    Log "FAILED: could not find an errors/warnings summary line in the compile log. See $compileLog"
    exit 1
}
