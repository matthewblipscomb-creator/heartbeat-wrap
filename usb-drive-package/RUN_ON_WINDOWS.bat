@echo off
REM heartbeat_wrap.sh cross-platform field test - Windows launcher.
REM
REM heartbeat_wrap.sh is a bash script. Windows has no native bash, so this
REM launcher looks for a bash-compatible layer already on the machine
REM (Git for Windows' "Git Bash", or WSL) and uses whichever it finds.
REM It does NOT install anything and does NOT require Administrator/root -
REM if neither is present it just tells you what to install.
setlocal enabledelayedexpansion

set SCRIPT_DIR=%~dp0
cd /d "%SCRIPT_DIR%"

echo ============================================================
echo  heartbeat_wrap.sh cross-platform field test - Windows
echo  Host: %COMPUTERNAME%
echo  Date: %DATE% %TIME%
echo ============================================================
echo.

REM --- Option 1: Git for Windows' bash.exe (installed with "Git Bash") ---
where bash.exe >nul 2>nul
if %ERRORLEVEL%==0 (
    echo Found bash.exe on PATH - using it to run run_test_mac_linux.sh
    echo (This is almost certainly Git Bash if Git for Windows is installed.)
    echo.
    bash.exe run_test_mac_linux.sh
    goto :done
)

REM --- Option 2: WSL (Windows Subsystem for Linux) ---
where wsl.exe >nul 2>nul
if %ERRORLEVEL%==0 (
    echo No bash.exe on PATH, but wsl.exe is available - trying WSL instead.
    echo NOTE: WSL sees this drive under /mnt/<letter>/... not the Windows
    echo path, so we cd into it using wslpath translation.
    echo.
    for /f "delims=" %%P in ('wsl.exe wslpath -a "%SCRIPT_DIR%"') do set WSL_DIR=%%P
    wsl.exe bash -c "cd '%WSL_DIR%' && bash run_test_mac_linux.sh"
    goto :done
)

REM --- Neither found ---
echo ============================================================
echo  NO BASH-COMPATIBLE SHELL FOUND ON THIS MACHINE
echo ============================================================
echo.
echo heartbeat_wrap.sh requires bash. Neither Git Bash nor WSL was
echo found on this system's PATH. To run this test, install ONE of:
echo.
echo   1. Git for Windows (includes Git Bash, no admin rights needed
echo      for a per-user install): https://git-scm.com/download/win
echo.
echo   2. WSL2 (requires an elevated/Administrator prompt once):
echo      Open PowerShell as Administrator and run:  wsl --install
echo.
echo Then re-run this RUN_ON_WINDOWS.bat file.
echo No Administrator/root access is needed for option 1.
echo.
pause
exit /b 1

:done
echo.
echo ============================================================
echo  Test run complete. Look in this folder for a
echo  results_*.txt file and bring it back for review.
echo ============================================================
pause
