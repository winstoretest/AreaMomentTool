@echo off
REM ============================================================================
REM  Alibre Extensions Build Script
REM  Builds the VSIX extension and all templates
REM  Configuration loaded from build.config.json
REM ============================================================================

cd /d "%~dp0"

echo.
echo  Building Extensions (configuration from build.config.json)...
echo.

powershell -ExecutionPolicy Bypass -File "%~dp0Build-All.ps1" %*

if errorlevel 1 (
    echo.
    echo  Build failed!
    pause
    exit /b 1
)

echo.
echo  Build complete! Check bin\ directory for outputs.
echo.
pause
