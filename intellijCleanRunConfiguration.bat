@echo off
setlocal ENABLEDELAYEDEXPANSION

rem Clean build configuration: wipe .compiled and copy .koreader into it
rem Usage:
rem   intellijCleanRunConfiguration.bat

set "SCRIPT_DIR=%~dp0"
set "SRC=%SCRIPT_DIR%.koreader"
set "DEST=%SCRIPT_DIR%.compiled"

echo ------------------------------------------------------------
echo Source:      "%SRC%"
echo Destination: "%DEST%"

rem Ensure source exists
if not exist "%SRC%" (
  echo [ERROR] Source folder not found: "%SRC%"
  echo Ensure a ".koreader" directory exists at the project root.
  echo.
  exit /b 1
)

rem Wipe destination completely on every run
if exist "%DEST%" (
  echo [INFO] Removing existing destination: "%DEST%"
  rmdir /s /q "%DEST%"
)

mkdir "%DEST%" >nul 2>&1

rem Copy all contents from .koreader to .compiled
rem Robocopy flags:
rem  /E       -> include subdirectories (including empty)
rem  /R:1     -> retry once on failure
rem  /W:1     -> wait 1 sec between retries
rem  /COPY:DAT-> copy Data, Attributes, Timestamps
rem  /NFL /NDL-> concise logging (no file/dir lists), keep summary
rem  /NP      -> no per-file progress

robocopy "%SRC%" "%DEST%" /E /R:1 /W:1 /COPY:DAT /NFL /NDL /NP
set "RC=%ERRORLEVEL%"

rem Robocopy returns codes: 0 (no files), 1 (some files copied) are success; 2-7 also often acceptable.
if %RC% LSS 8 (
  echo [SUCCESS] Synchronized .koreader to .compiled
  echo.
  echo [INFO] Executing intellijRunConfiguration.bat...
  call "%SCRIPT_DIR%intellijRunConfiguration.bat" %*
  set "RUN_RC=%ERRORLEVEL%"
  if not %RUN_RC%==0 (
    echo [ERROR] intellijRunConfiguration.bat failed with exit code %RUN_RC%.
    exit /b %RUN_RC%
  ) else (
    echo [SUCCESS] intellijRunConfiguration.bat completed successfully.
    exit /b 0
  )
) else (
  echo [ERROR] Robocopy failed with exit code %RC%.
  echo.
  exit /b %RC%
)
