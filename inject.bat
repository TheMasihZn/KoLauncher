@echo off
setlocal EnableDelayedExpansion

set "SCRIPT_DIR=%~dp0"
set "SRC=%SCRIPT_DIR%mine\koreader\plugins"
set "DEST=%SCRIPT_DIR%.compiled\koreader\plugins"

if not exist "%SRC%" (
    echo [ERROR] Source folder not found: "%SRC%"
    exit /b 1
)

rem Create destination if it doesn't exist
mkdir "%DEST%" 2>nul

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
        mkdir "%DEST%\!PLUGIN_NAME!" 2>nul
    )

    rem Copy plugin contents using robocopy, excluding data directory
    robocopy "%%D" "%DEST%\!PLUGIN_NAME!" /E /R:1 /W:1 /COPY:DAT /XD "%DEST%\!PLUGIN_NAME!\data" /NFL /NDL /NP
)

if !ERRORLEVEL! LSS 8 (
    echo [SUCCESS] KOReader files synchronized to local .compiled at %DEST%\
    echo.
    rem ------------------------------------------------------------
    rem Now mirror from .compiled to the connected Kindle
    rem Destination on Kindle: <Drive>:\koreader\plugins
    set "KINDLE_DEST=%KINDLE_DRIVE%\koreader\plugins"
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
    rem Copy plugin contents from .compiled to Kindle only if the Kindle is found
    for %%D in (A B C D E F G H I J K L M N O P Q R S T U V W X Y Z) do (
        if exist "%%D:\koreader\plugins" (
            set "KINDLE_DRIVE=%%D:"
            set "KINDLE_DEST=%%D:\koreader\plugins"
            
            for /d %%D in ("%DEST%\*") do (
                if exist "%KINDLE_DEST%\%%~nxD" (
                    set "PLUGIN_NAME=%%~nxD"
                    robocopy "%%D" "%KINDLE_DEST%\!PLUGIN_NAME!" /E /R:1 /W:1 /COPY:DAT /XD "%KINDLE_DEST%\!PLUGIN_NAME!\data" /NFL /NDL /NP
                )
            )
        )
    )
    set "RC2=%ERRORLEVEL%"

    if !RC2! LSS 8 (
        echo [SUCCESS] KOReader plugins deployed to Kindle at %KINDLE_DEST%\
        echo.
        exit /b 0
    ) else (