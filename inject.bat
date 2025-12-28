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

rem Stage 2: SFTP configuration
set "SFTP_HOST=192.168.218.78"
set "SFTP_PORT=2222"
set "SFTP_USER=root"
set "SFTP_REMOTE_BASE=/mnt/us/koreader"

rem TIP: To avoid entering a password every time, use SSH keys:
rem 1. Generate keys locally: ssh-keygen -t ed25519
rem 2. Copy to Kindle: type %USERPROFILE%\.ssh\id_ed25519.pub | ssh -p %SFTP_PORT% %SFTP_USER%@%SFTP_HOST% "cat >> /root/.ssh/authorized_keys"

if not "%~1"=="" (
  set "SFTP_HOST=%~1"
)

echo Connecting to SFTP: %SFTP_USER%@%SFTP_HOST%:%SFTP_PORT%
echo Remote base path: %SFTP_REMOTE_BASE%

rem Stage 3: deploy to Kindle via SFTP
echo Deploying plugins to Kindle via SFTP
echo Note: If prompted, enter the password for %SFTP_USER%@%SFTP_HOST%

rem We use scp for recursive copy. 
rem This copies the local 'plugins' folder (%DEST%) into the remote base path.
rem -o StrictHostKeyChecking=accept-new allows automatic acceptance of new host keys.
scp -o StrictHostKeyChecking=accept-new -P %SFTP_PORT% -r "%DEST%" "%SFTP_USER%@%SFTP_HOST%:%SFTP_REMOTE_BASE%/"

echo ...

if %ERRORLEVEL% equ 0 (
  echo [SUCCESS] KOReader plugins deployed to Kindle at %SFTP_HOST%:%SFTP_REMOTE_BASE%/plugins
  
  echo:
  set /p "RUN_SHELL=Open interactive SSH shell? (y/n): "
  if /i "%RUN_SHELL%"=="y" (
    echo Opening SSH shell to %SFTP_HOST%...
    ssh -o StrictHostKeyChecking=accept-new -t -p %SFTP_PORT% "%SFTP_USER%@%SFTP_HOST%"
  )
) else (
  echo [ERROR] Failed to deploy plugins via SFTP.
  exit /b 1
)

echo:
exit /b 0