@echo off
setlocal EnableExtensions

rem Resolve paths
set "SCRIPT_DIR=%~dp0"
set "SRC=%SCRIPT_DIR%mine\koreader\plugins"
set "DEST=%SCRIPT_DIR%.compiled\koreader\plugins"

if not exist "%SRC%" (
  echo [ERROR] Source folder not found: "%SRC%"
  exit /b 1
)

rem Ensure local compiled destination
if not exist "%DEST%" mkdir "%DEST%" >nul 2>&1

rem Stage 1: mirror workspace plugins to .compiled (non-destructive, exclude 'data')
for /d %%D in ("%SRC%\*") do (
  if not exist "%DEST%\%%~nxD" mkdir "%DEST%\%%~nxD" >nul 2>&1
  echo Processing plugin: %%~nxD
  robocopy "%%D" "%DEST%\%%~nxD" /E /R:1 /W:1 /COPY:DAT /XD "data" /NFL /NDL /NP >nul
)

echo [SUCCESS] KOReader files synchronized to local .compiled at %DEST%\
echo:

rem Stage 2: detect Kindle drive
set "KINDLE_DRIVE="
if not "%~1"=="" (
  set "KINDLE_DRIVE=%~1"
)

if "%KINDLE_DRIVE%"=="" (
  for %%X in (A B C D E F G H I J K L M N O P Q R S T U V W X Y Z) do (
    if exist "%%X:\" if exist "%%X:\koreader" (
      set "KINDLE_DRIVE=%%X:"
      goto :FOUND_DRIVE
    )
  )
)

if "%KINDLE_DRIVE%"=="" (
  rem Try to create expected path on any removable drive
  for %%X in (A B C D E F G H I J K L M N O P Q R S T U V W X Y Z) do (
    if exist "%%X:\" (
      mkdir "%%X:\koreader\plugins" >nul 2>&1
      if exist "%%X:\koreader\plugins" (
        set "KINDLE_DRIVE=%%X:"
        goto :FOUND_DRIVE
      )
    )
  )
)

if "%KINDLE_DRIVE%"=="" (
  echo [ERROR] Could not find Kindle drive (no X:\koreader or X:\koreader\plugins).
  exit /b 1
)

:FOUND_DRIVE
set "KINDLE_DEST=%KINDLE_DRIVE%\koreader\plugins"
if not exist "%KINDLE_DEST%" mkdir "%KINDLE_DEST%" >nul 2>&1
echo Kindle destination: "%KINDLE_DEST%"

rem Stage 3: deploy to Kindle (non-destructive, exclude 'data')
for /d %%P in ("%DEST%\*") do (
  if not exist "%KINDLE_DEST%\%%~nxP" mkdir "%KINDLE_DEST%\%%~nxP" >nul 2>&1
  echo Deploying plugin to Kindle: %%~nxP
  robocopy "%%P" "%KINDLE_DEST%\%%~nxP" /E /R:1 /W:1 /COPY:DAT /XD "data" /NFL /NDL /NP >nul
)

echo [SUCCESS] KOReader plugins deployed to Kindle at %KINDLE_DEST%\
echo:
exit /b 0