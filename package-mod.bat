@echo off
setlocal

REM ========================================
REM EDIT THIS: Set your mod name
REM ========================================
set MOD_NAME=QoL-Tweaks

REM ========================================
REM Script Configuration (no need to edit)
REM ========================================
set ZIP_NAME=%MOD_NAME%.zip
set TEMP_DIR=%TEMP%\%MOD_NAME%_package
set MOD_PATH=ue4ss\Mods\%MOD_NAME%

echo Packaging %MOD_NAME%...

REM Clean up old temp directory and zip file
if exist "%TEMP_DIR%" rmdir /s /q "%TEMP_DIR%"
if exist "%ZIP_NAME%" del /q "%ZIP_NAME%"

REM Create temp directory structure
mkdir "%TEMP_DIR%\%MOD_PATH%\scripts"

REM Copy files
echo Copying files...

REM Copy config.lua if it exists
if exist "config.lua" (
    copy "config.lua" "%TEMP_DIR%\%MOD_PATH%\config.lua" >nul
    echo   - config.lua
) else (
    echo   - config.lua (not found, skipping)
)

REM Copy enabled.txt
if exist "enabled.txt" (
    copy "enabled.txt" "%TEMP_DIR%\%MOD_PATH%\enabled.txt" >nul
    echo   - enabled.txt
) else (
    echo WARNING: enabled.txt not found!
)

REM Copy scripts folder contents
if exist "scripts\main.lua" (
    copy "scripts\main.lua" "%TEMP_DIR%\%MOD_PATH%\scripts\main.lua" >nul
    echo   - scripts\main.lua
) else (
    echo WARNING: scripts\main.lua not found!
)

REM Create zip using PowerShell
echo Creating zip file...
powershell -Command "Compress-Archive -Path '%TEMP_DIR%\*' -DestinationPath '%ZIP_NAME%' -Force"

REM Clean up temp directory
rmdir /s /q "%TEMP_DIR%"

echo.
echo Done! Created: %ZIP_NAME%
echo.
pause
