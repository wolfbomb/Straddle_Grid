@echo off
setlocal enabledelayedexpansion
REM ============================================================
REM  Hydra — automated Strategy Tester runs
REM  EDIT THE TWO PATHS BELOW BEFORE FIRST RUN
REM ============================================================
set "TERMINAL=C:\Program Files\MetaTrader 5\terminal64.exe"
set "DATADIR=C:\Users\YOURNAME\AppData\Roaming\MetaQuotes\Terminal\YOUR-TERMINAL-ID"
REM   ^ MT5: File -> Open Data Folder, copy that path here
REM ============================================================

if not exist "%TERMINAL%" (
    echo [ERROR] terminal64.exe not found at: %TERMINAL%
    echo         Edit TERMINAL at the top of this script.
    pause & exit /b 1
)
if not exist "%DATADIR%\MQL5\Presets" (
    echo [ERROR] Data folder not found at: %DATADIR%
    echo         Edit DATADIR at the top of this script.
    pause & exit /b 1
)
if not exist "%DATADIR%\MQL5\Experts\SIGMA\Straddle_Grid.ex5" (
    echo [WARN] Compiled EA not found at MQL5\Experts\SIGMA\Straddle_Grid.ex5
    echo        Compile Straddle_Grid.mq5 in MetaEditor first, then rerun.
    pause & exit /b 1
)

echo Copying presets to MQL5\Presets ...
copy /Y "%~dp0presets\*.set" "%DATADIR%\MQL5\Presets\" >nul

echo.
echo NOTE: MetaTrader 5 must be CLOSED before the runs start.
echo Each run opens its own terminal, tests, writes a report, and exits.
echo First run per date range downloads tick data - be patient.
echo.
pause

for %%C in ("%~dp0configs\*.ini") do (
    echo ------------------------------------------------------------
    echo Running %%~nxC ...
    "%TERMINAL%" /config:"%%~fC"
    echo Finished %%~nxC
)

echo ------------------------------------------------------------
echo All runs done.
echo   Reports:      %DATADIR%\Hydra_0*.htm
echo   Tester logs:  %DATADIR%\Tester\*\logs\  (the [HYDRA] lines live here)
echo Send both back for verification.
pause
