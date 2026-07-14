@echo off
setlocal enabledelayedexpansion
REM ============================================================
REM  Hydra - automated Strategy Tester runs (Windows)
REM
REM  Auto-detects the repo-as-data-folder layout (terminal64.exe and
REM  MQL5\ in the repo root, e.g. D:\Straddle_Grid). If your setup
REM  differs, edit TERMINAL / DATADIR in the OVERRIDES block below.
REM ============================================================

REM ---- OVERRIDES (leave empty for auto-detection) -------------
set "TERMINAL="
set "DATADIR="
REM   DATADIR = MT5 data folder (MT5: File -> Open Data Folder)
REM   TERMINAL = full path to terminal64.exe
REM --------------------------------------------------------------

for %%I in ("%~dp0..\..") do set "REPO_ROOT=%%~fI"

if not defined DATADIR if exist "%REPO_ROOT%\MQL5\Experts\SIGMA" set "DATADIR=%REPO_ROOT%"
if not defined DATADIR (
    echo [ERROR] MT5 data folder not auto-detected.
    echo         Edit DATADIR at the top of this script
    echo         ^(MT5: File -^> Open Data Folder shows the path^).
    pause & exit /b 1
)

if not defined TERMINAL if exist "%DATADIR%\terminal64.exe" set "TERMINAL=%DATADIR%\terminal64.exe"
if not defined TERMINAL if exist "C:\Program Files\MetaTrader 5\terminal64.exe" set "TERMINAL=C:\Program Files\MetaTrader 5\terminal64.exe"
if not defined TERMINAL (
    echo [ERROR] terminal64.exe not found.
    echo         Edit TERMINAL at the top of this script.
    pause & exit /b 1
)

REM /portable keeps the tester writing into DATADIR when the terminal
REM lives inside it (repo-as-data-folder layout).
set "PORTABLE="
if /I "%TERMINAL%"=="%DATADIR%\terminal64.exe" set "PORTABLE=/portable"

if not exist "%DATADIR%\MQL5\Experts\SIGMA\Straddle_Grid.ex5" (
    echo [WARN] Compiled EA not found at MQL5\Experts\SIGMA\Straddle_Grid.ex5
    echo        Compile Straddle_Grid.mq5 in MetaEditor first, then rerun.
    pause & exit /b 1
)

if not exist "%~dp0configs\common.local.ini" (
    echo [ERROR] Missing configs\common.local.ini ^(your MT5 DEMO login/password/server^).
    echo.
    echo         MT5's command-line tester needs an authenticated [Common] session to
    echo         actually run automated tests. Without it, terminal64.exe silently opens
    echo         your normal saved terminal session instead of testing - no error, no
    echo         report ^(this is what happened on 2026-07-14: it just recovered the
    echo         live/demo position and pending orders already on the default profile^).
    echo.
    echo         Fix: copy configs\common.local.ini.example to configs\common.local.ini
    echo         and fill in your DEMO account's Login/Password/Server. That file is
    echo         gitignored - it will never be committed.
    pause & exit /b 1
)

echo Terminal:    %TERMINAL% %PORTABLE%
echo Data folder: %DATADIR%
echo.
echo Copying presets (UTF-16 conversion) to MQL5\Presets ...
if not exist "%DATADIR%\MQL5\Presets" mkdir "%DATADIR%\MQL5\Presets"
REM MT5 expects .set files in UTF-16LE; plain UTF-8 is silently ignored
REM and the run falls back to default inputs.
powershell -NoProfile -Command "Get-ChildItem '%~dp0presets\*.set' | ForEach-Object { Get-Content $_.FullName | Set-Content -Encoding Unicode (Join-Path '%DATADIR%\MQL5\Presets' $_.Name) }"

echo.
echo Merging your local login into each test config ...
if not exist "%~dp0.merged" mkdir "%~dp0.merged"
for %%C in ("%~dp0configs\*.ini") do (
    if /I not "%%~nxC"=="common.local.ini" (
        copy /b "%~dp0configs\common.local.ini"+"%%C" "%~dp0.merged\%%~nxC" >nul
    )
)

echo.
echo NOTE: MetaTrader 5 must be CLOSED before the runs start.
echo Each run opens its own terminal, tests, writes a report, and exits.
echo First run per date range downloads tick data - be patient.
echo.
pause

for %%C in ("%~dp0configs\*.ini") do (
    if /I not "%%~nxC"=="common.local.ini" (
        echo ------------------------------------------------------------
        echo Running %%~nxC ...
        "%TERMINAL%" %PORTABLE% /config:"%~dp0.merged\%%~nxC"
        echo Finished %%~nxC
    )
)

echo ------------------------------------------------------------
echo All runs done.
echo   Reports:      %DATADIR%\Hydra_0*.htm
echo   Tester logs:  %DATADIR%\Tester\*\logs\  (the [HYDRA] lines live here)
echo Send both back for verification.
pause
