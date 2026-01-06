@echo off
REM ============================================================================
REM  Build Installers for Alibre Design Add-Ons
REM  Generates Inno Setup (.iss) scripts and compiles installers
REM  Configuration loaded from build.config.json
REM ============================================================================

cd /d "%~dp0"

echo.
echo ================================================================================
echo   ALIBRE DESIGN INSTALLER BUILDER
echo   (Configuration from build.config.json)
echo ================================================================================
echo.

powershell -ExecutionPolicy Bypass -File "%~dp0Build-Installers.ps1" %*

if errorlevel 1 (
    echo.
    echo ================================================================================
    echo   INSTALLER BUILD FAILED
    echo   Check output above for details
    echo ================================================================================
    echo.
    pause
    exit /b 1
)

pause
exit /b 0
