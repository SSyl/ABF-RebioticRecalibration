@echo off
setlocal EnableDelayedExpansion

REM ========================================
REM Setup ANSI color codes
REM ========================================
for /F %%a in ('echo prompt $E ^| cmd') do set "ESC=%%a"
set "C_RESET=%ESC%[0m"
set "C_CYAN=%ESC%[96m"
set "C_GREEN=%ESC%[92m"
set "C_YELLOW=%ESC%[93m"
set "C_RED=%ESC%[91m"
set "C_DIM=%ESC%[90m"

REM ========================================
REM Auto-detect mod name from parent folder
REM ========================================
for %%I in (.) do set DETECTED_NAME=%%~nxI

echo %C_CYAN%========================================%C_RESET%
echo %C_CYAN%  Packaging: %DETECTED_NAME%%C_RESET%
echo %C_CYAN%========================================%C_RESET%
echo.

REM ========================================
REM Pre-flight validation
REM ========================================
set VALIDATION_FAILED=0

if not exist "scripts" (
    echo %C_RED%[ERROR] scripts folder not found!%C_RESET%
    set VALIDATION_FAILED=1
)

if not exist "scripts\main.lua" (
    echo %C_RED%[ERROR] scripts\main.lua not found!%C_RESET%
    set VALIDATION_FAILED=1
)

if not exist "enabled.txt" (
    echo %C_YELLOW%[WARNING] enabled.txt not found - mod won't auto-enable%C_RESET%
    echo.
)

if %VALIDATION_FAILED%==1 (
    echo.
    echo %C_RED%Packaging aborted due to errors.%C_RESET%
    pause
    exit /b 1
)

REM ========================================
REM Show files to package
REM ========================================
echo Files to package:
echo %C_DIM%----------------------------------------%C_RESET%

set FILE_COUNT=0
set /a TOTAL_SIZE=0

if exist "config.lua" (
    for %%A in ("config.lua") do (
        set /a TOTAL_SIZE+=%%~zA
        set /a FILE_COUNT+=1
        call :FormatSize %%~zA
        echo   config.lua - [%C_CYAN%!FORMATTED_SIZE!%C_RESET%]
    )
)

if exist "enabled.txt" (
    for %%A in ("enabled.txt") do (
        set /a TOTAL_SIZE+=%%~zA
        set /a FILE_COUNT+=1
        call :FormatSize %%~zA
        echo   enabled.txt - [%C_CYAN%!FORMATTED_SIZE!%C_RESET%]
    )
)

REM Recursively find all .lua files in scripts folder
for /R scripts %%F in (*.lua) do (
    set /a TOTAL_SIZE+=%%~zF
    set /a FILE_COUNT+=1
    call :FormatSize %%~zF
    set "FULL_PATH=%%F"
    set "REL_PATH=!FULL_PATH:%CD%\=!"
    echo   !REL_PATH! - [%C_CYAN%!FORMATTED_SIZE!%C_RESET%]
)

call :FormatSize !TOTAL_SIZE!
echo %C_DIM%----------------------------------------%C_RESET%
echo   Total: %C_GREEN%!FILE_COUNT! files%C_RESET% - [%C_CYAN%!FORMATTED_SIZE!%C_RESET%]
echo.

REM ========================================
REM Mod name prompt
REM ========================================
echo Mod name: %C_GREEN%%DETECTED_NAME%%C_RESET%
echo %C_DIM%Press Enter to use, or type a new name:%C_RESET%
set /p MOD_NAME_INPUT="> "

if defined MOD_NAME_INPUT (
    set MOD_NAME=!MOD_NAME_INPUT!
) else (
    set MOD_NAME=%DETECTED_NAME%
)

echo.

REM ========================================
REM Version prompt
REM ========================================
echo Enter version number %C_DIM%(e.g., 1.0.0)%C_RESET%
echo %C_DIM%Leave blank to skip version suffix:%C_RESET%
set /p VERSION="> "

if defined VERSION (
    set ZIP_NAME=!MOD_NAME!-v!VERSION!.zip
) else (
    set ZIP_NAME=!MOD_NAME!.zip
)

echo.

REM ========================================
REM Script Configuration
REM ========================================
set TEMP_DIR=%TEMP%\%MOD_NAME%_package
set MOD_PATH=ue4ss\Mods\%MOD_NAME%

REM Clean up old temp directory and zip file
if exist "%TEMP_DIR%" rmdir /s /q "%TEMP_DIR%"
if exist "!ZIP_NAME!" del /q "!ZIP_NAME!"

REM Create temp directory structure
mkdir "%TEMP_DIR%\%MOD_PATH%\scripts"

REM ========================================
REM Copy files
REM ========================================
if exist "config.lua" (
    copy "config.lua" "%TEMP_DIR%\%MOD_PATH%\config.lua" >nul
)

if exist "enabled.txt" (
    copy "enabled.txt" "%TEMP_DIR%\%MOD_PATH%\enabled.txt" >nul
)

REM Recursively copy all .lua files preserving folder structure
for /R scripts %%F in (*.lua) do (
    set "FULL_PATH=%%F"
    set "REL_PATH=!FULL_PATH:%CD%\=!"
    set "DEST_DIR=%TEMP_DIR%\%MOD_PATH%\%%~dpF"
    set "DEST_DIR=!DEST_DIR:%CD%\=!"
    if not exist "!DEST_DIR!" mkdir "!DEST_DIR!"
    copy "%%F" "%TEMP_DIR%\%MOD_PATH%\!REL_PATH!" >nul
)

REM ========================================
REM Create zip using PowerShell
REM ========================================
echo Creating %C_YELLOW%!ZIP_NAME!%C_RESET%...
powershell -Command "Compress-Archive -Path '%TEMP_DIR%\*' -DestinationPath '!ZIP_NAME!' -Force"

REM Clean up temp directory
rmdir /s /q "%TEMP_DIR%"

REM Show final zip size
for %%A in ("!ZIP_NAME!") do (
    call :FormatSize %%~zA
    echo.
    echo %C_GREEN%Created%C_RESET% !ZIP_NAME! [%C_CYAN%!FORMATTED_SIZE!%C_RESET%]
    echo %C_DIM%%CD%\!ZIP_NAME!%C_RESET%
)
echo.
pause
goto :eof

REM ========================================
REM Function: Format bytes to human readable
REM ========================================
:FormatSize
set BYTES=%1
if !BYTES! EQU 0 (
    set FORMATTED_SIZE=0 B
    goto :eof
)
if !BYTES! LSS 1024 (
    set FORMATTED_SIZE=!BYTES! B
    goto :eof
)
if !BYTES! LSS 1048576 (
    set /a KB=BYTES*10/1024
    set /a KB_INT=KB/10
    set /a KB_DEC=KB%%10
    set FORMATTED_SIZE=!KB_INT!.!KB_DEC! KB
    goto :eof
)
if !BYTES! LSS 1073741824 (
    set /a MB=BYTES*10/1048576
    set /a MB_INT=MB/10
    set /a MB_DEC=MB%%10
    set FORMATTED_SIZE=!MB_INT!.!MB_DEC! MB
    goto :eof
)
set /a GB=BYTES*10/1073741824
set /a GB_INT=GB/10
set /a GB_DEC=GB%%10
set FORMATTED_SIZE=!GB_INT!.!GB_DEC! GB
goto :eof
