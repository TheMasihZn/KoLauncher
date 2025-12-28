@echo off
setlocal EnableExtensions

rem Resolve paths
set "SCRIPT_DIR=%~dp0"
set "SRC_BASE=%SCRIPT_DIR%mine\koreader\plugins"
set "DEST_BASE=%SCRIPT_DIR%.compiled\koreader\plugins"

rem Check for plugin name argument
set "PLUGIN_NAME=%~1"

if "%PLUGIN_NAME%"=="" (
    echo [ERROR] No plugin name provided.
    echo Usage: %~nx0 ^<plugin_folder_name^> [ip_address]
    echo Example: %~nx0 estekhareh.koplugin 192.168.218.78
    exit /b 1
)

set "SRC=%SRC_BASE%\%PLUGIN_NAME%"
set "DEST=%DEST_BASE%\%PLUGIN_NAME%"

if not exist "%SRC%" (
    echo [ERROR] Plugin folder not found: "%SRC%"
    exit /b 1
)

rem Ensure local compiled destination
if not exist "%DEST_BASE%" mkdir "%DEST_BASE%" >nul 2>&1

rem Stage 1: mirror workspace plugin to .compiled (non-destructive, exclude 'data')
if not exist "%DEST%" mkdir "%DEST%" >nul 2>&1
echo Processing plugin: %PLUGIN_NAME%
robocopy "%SRC%" "%DEST%" /E /R:1 /W:1 /COPY:DAT /XD "data" /NFL /NDL /NP >nul

echo [SUCCESS] Plugin %PLUGIN_NAME% synchronized to local .compiled
echo:

rem Stage 2: SFTP configuration
set "SFTP_HOST=192.168.218.78"
set "SFTP_PORT=2222"
set "SFTP_USER=root"
set "SFTP_REMOTE_BASE=/mnt/us/koreader/plugins"

rem TIP: To avoid entering a password every time, use SSH keys:
rem 1. Generate keys locally: ssh-keygen -t ed25519
rem 2. Copy to Kindle: type %USERPROFILE%\.ssh\id_ed25519.pub | ssh -p %SFTP_PORT% %SFTP_USER%@%SFTP_HOST% "cat >> /root/.ssh/authorized_keys"

rem If second argument is provided, use it as SFTP_HOST
if not "%~2"=="" (
    set "SFTP_HOST=%~2"
)

echo Connecting to SFTP: %SFTP_USER%@%SFTP_HOST%:%SFTP_PORT%
echo Remote destination path: %SFTP_REMOTE_BASE%/%PLUGIN_NAME%

rem Stage 3: deploy to Kindle via SFTP
echo Deploying plugin %PLUGIN_NAME% to Kindle via SFTP...
echo Note: If prompted, enter the password for %SFTP_USER%@%SFTP_HOST%

rem We use scp for recursive copy. 
rem We copy the specific plugin folder to the remote plugins directory.
rem -o StrictHostKeyChecking=accept-new allows automatic acceptance of new host keys.
scp -o StrictHostKeyChecking=accept-new -P %SFTP_PORT% -r "%DEST%" "%SFTP_USER%@%SFTP_HOST%:%SFTP_REMOTE_BASE%/"

if %ERRORLEVEL% equ 0 (
    echo [SUCCESS] Plugin %PLUGIN_NAME% deployed to Kindle at %SFTP_HOST%:%SFTP_REMOTE_BASE%/%PLUGIN_NAME%
    
    echo:
    set /p "RUN_SHELL=Open interactive SSH shell? (y/n): "
    if /i "%RUN_SHELL%"=="y" (
        echo Opening SSH shell to %SFTP_HOST%...
        ssh -o StrictHostKeyChecking=accept-new -t -p %SFTP_PORT% "%SFTP_USER%@%SFTP_HOST%"
    )
) else (
    echo [ERROR] Failed to deploy plugin via SFTP.
    exit /b 1
)

echo:
exit /b 0
