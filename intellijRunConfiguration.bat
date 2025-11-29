@echo off
setlocal ENABLEDELAYEDEXPANSION

rem Run configuration: Copy all contents of the src folder to the connected Kindle over USB.
rem Usage:
rem   run.bat              -> auto-detect Kindle drive by volume label "Kindle"
rem   run.bat K            -> use K: as the Kindle drive
rem   run.bat K:           -> same as above

set "SCRIPT_DIR=%~dp0"
set "SRC=%SCRIPT_DIR%mine\koreader\plugins"

rem Determine project name from folder containing this script
for %%I in ("%SCRIPT_DIR%.") do set "PROJECT_NAME=%%~nxI"

if not exist "%SRC%" (
  echo [ERROR] Source folder not found: "%SRC%"
  echo Ensure the project structure contains a "src" directory next to run.bat.
  echo.
  pause
  exit /b 1
)

set "KINDLE_DRIVE_RAW=%~1"
if defined KINDLE_DRIVE_RAW (
  rem Normalize provided drive letter (accept K or K:)
  set "KINDLE_DRIVE_RAW=!KINDLE_DRIVE_RAW::=!"
  set "KINDLE_DRIVE=!KINDLE_DRIVE_RAW!:"
  goto :HaveDrive
)

rem Attempt 1: Use PowerShell Get-Volume to find volume label "Kindle"
for /f "usebackq delims=" %%D in (`powershell -NoProfile -Command "^$vol=Get-Volume -ErrorAction SilentlyContinue ^| Where-Object { ^$_.FileSystemLabel -eq 'Kindle' } ^| Select-Object -First 1 -ExpandProperty DriveLetter; if(^$vol){Write-Output ^"^${vol}^:"}"`) do (
      set "KINDLE_DRIVE=%%D"
    )

    if defined KINDLE_DRIVE goto :HaveDrive

rem Attempt 2: Fallback to WMIC (deprecated but widely available)
for /f "tokens=1,2" %%A in ('wmic logicaldisk get name^, volumename ^| findstr ":"') do (
  if /I "%%B"=="Kindle" (
    set "KINDLE_DRIVE=%%A"
  )
)

if defined KINDLE_DRIVE goto :HaveDrive

echo [INFO] Could not auto-detect Kindle drive by volume label "Kindle".
set /p KINDLE_DRIVE_RAW=Please enter the Kindle drive letter (e.g., K): 
if not defined KINDLE_DRIVE_RAW (
  echo [ERROR] No drive letter provided. Aborting.
  echo.
  pause
  exit /b 2
)
set "KINDLE_DRIVE_RAW=%KINDLE_DRIVE_RAW::=%"
set "KINDLE_DRIVE=%KINDLE_DRIVE_RAW%:"

:HaveDrive
if not exist "%KINDLE_DRIVE%\" (
  echo [ERROR] Drive "%KINDLE_DRIVE%" not found. Ensure your Kindle is connected via USB and appears as a drive.
  echo.
  pause
  exit /b 3
)

echo ------------------------------------------------------------
echo Source:      "%SRC%"
set "DEST=%SCRIPT_DIR%.compiled\koreader\plugins"

rem Ensure destination directory exists
mkdir "%DEST%" >nul 2>&1

echo Destination: "%DEST%"

rem Process each plugin folder
for /d %%D in ("%SRC%\*") do (
    set "PLUGIN_NAME=%%~nxD"
    echo Processing plugin: !PLUGIN_NAME!

    rem Remove existing plugin folder except data directory
    if exist "%DEST%\!PLUGIN_NAME!" (
        for /d %%F in ("%DEST%\!PLUGIN_NAME!\*") do (
            if /i not "%%~nxF"=="data" (
                rmdir /s /q "%%F"
            )
        )
        for %%F in ("%DEST%\!PLUGIN_NAME!\*.*") do (
            del /q "%%F"
        )
    ) else (
        mkdir "%DEST%\!PLUGIN_NAME!" >nul 2>&1
    )
)
echo ------------------------------------------------------------

rem Copy plugin contents using ROBOCOPY, excluding data directory
rem Flags:
rem  /E   -> include subdirectories (including empty)
rem  /R:1 -> retry once on failure
rem  /W:1 -> wait 1 sec between retries
rem  /COPY:DAT -> copy Data, Attributes, Timestamps
rem  /XD  -> exclude directories
rem  /NFL /NDL -> concise logging (no file/dir lists), keep summary
rem  /NP -> no progress per file

for /d %%D in ("%SRC%\*") do (
    set "PLUGIN_NAME=%%~nxD"
    robocopy "%%D" "%DEST%\!PLUGIN_NAME!" /E /R:1 /W:1 /COPY:DAT /XD "%DEST%\!PLUGIN_NAME!\data" /NFL /NDL /NP
)
set "RC=%ERRORLEVEL%"

rem Robocopy returns codes: 0 (no files), 1 (some files copied) are success; 2-7 also often acceptable.
rem We treat 0-7 as success and others as error.
if %RC% LSS 8 (
  echo [SUCCESS] KOReader files synchronized to local .compiled at %DEST%\
  echo.
  rem ------------------------------------------------------------
  rem Now mirror from .compiled to the connected Kindle
  rem Destination on Kindle: <Drive>:\extensions\koreader\plugins
  set "KINDLE_DEST=%KINDLE_DRIVE%\extensions\koreader\plugins"
  echo Kindle destination: "%KINDLE_DEST%"

  rem Ensure Kindle destination exists
  mkdir "%KINDLE_DEST%" >nul 2>&1

  rem Clean each Kindle plugin folder except its data directory
  for /d %%D in ("%DEST%\*") do (
      set "PLUGIN_NAME=%%~nxD"
      echo Preparing Kindle plugin: !PLUGIN_NAME!
      if exist "%KINDLE_DEST%\!PLUGIN_NAME!" (
          for /d %%F in ("%KINDLE_DEST%\!PLUGIN_NAME!\*") do (
              if /i not "%%~nxF"=="data" (
                  rmdir /s /q "%%F"
              )
          )
          for %%F in ("%KINDLE_DEST%\!PLUGIN_NAME!\*.*") do (
              del /q "%%F"
          )
      ) else (
          mkdir "%KINDLE_DEST%\!PLUGIN_NAME!" >nul 2>&1
      )
  )

  rem Copy plugin contents from .compiled to Kindle, excluding data directories
  for /d %%D in ("%DEST%\*") do (
      set "PLUGIN_NAME=%%~nxD"
      robocopy "%%D" "%KINDLE_DEST%\!PLUGIN_NAME!" /E /R:1 /W:1 /COPY:DAT /XD "%KINDLE_DEST%\!PLUGIN_NAME!\data" /NFL /NDL /NP
  )
  set "RC2=%ERRORLEVEL%"

  if !RC2! LSS 8 (
      echo [SUCCESS] KOReader plugins deployed to Kindle at %KINDLE_DEST%\
      echo.
      exit /b 0
  ) else (
      echo [ERROR] Robocopy to Kindle failed with exit code !RC2!.
      echo.
      exit /b !RC2!
  )
) else (
  echo [ERROR] Robocopy failed with exit code %RC%.
  echo.
  exit /b %RC%
)
