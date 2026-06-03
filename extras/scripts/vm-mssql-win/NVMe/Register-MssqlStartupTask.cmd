@echo off
REM ============================================================================
REM Register-MssqlStartupTask.cmd
REM
REM Run this script ONCE as Administrator to:
REM   1. Set SQL Server and SQL Agent services to Manual startup
REM   2. Register a scheduled task that runs Set-MssqlStartupConfiguration.ps1
REM      on every VM boot (AtStartup trigger, runs as SYSTEM)
REM
REM Prerequisites:
REM   - Place Set-MssqlStartupConfiguration.ps1 in C:\Scripts\
REM   - Run this script from an elevated (Administrator) command prompt
REM ============================================================================

echo.
echo === Setting SQL Server services to Manual startup ===
sc config MSSQLSERVER start= demand
sc config SQLSERVERAGENT start= demand

echo.
echo === Registering scheduled task: SQL Server Startup - Ephemeral Storage ===

powershell.exe -NoProfile -ExecutionPolicy Bypass -File "%~dp0Register-MssqlStartupTask.ps1"

echo.
if %ERRORLEVEL% EQU 0 (
    echo === SUCCESS: Scheduled task registered. ===
    echo.
    echo On every VM start, the task will:
    echo   1. Detect and pool RAW NVMe disks via Storage Spaces
    echo   2. Format and assign the temp drive letter
    echo   3. Create the SQLTEMP folder with correct permissions
    echo   4. Start SQL Server and SQL Agent services
) else (
    echo === FAILED: Could not register scheduled task. Ensure you are running as Administrator. ===
)

echo.
pause
