@echo off
REM ============================================================================
REM  Full Build Pipeline with Installers
REM  Runs: build-full (tests, VSIX, NuGet) -> Build-Installers (Inno Setup)
REM  Configuration loaded from build.config.json
REM ============================================================================

cd /d "%~dp0"

echo.
echo ================================================================================
echo   FULL BUILD PIPELINE WITH INSTALLERS
echo   (Configuration from build.config.json)
echo ================================================================================
echo.

REM ============================================================================
REM  STEP 1: Run Full Build Pipeline
REM ============================================================================
echo.
echo ================================================================================
echo   STEP 1: Full Build Pipeline (VSIX + NuGet)
echo ================================================================================
call "%~dp0build-full.cmd"
if errorlevel 1 (
    echo.
    echo ================================================================================
    echo   PIPELINE ABORTED - build-full.cmd failed
    echo ================================================================================
    pause
    exit /b 1
)

REM ============================================================================
REM  STEP 2: Build Installers
REM ============================================================================
echo.
echo ================================================================================
echo   STEP 2: Building Installers (Inno Setup)
echo ================================================================================
echo.

powershell -ExecutionPolicy Bypass -File "%~dp0Build-Installers.ps1" -Configuration Release
if errorlevel 1 (
    echo.
    echo ================================================================================
    echo   WARNING - Some installers failed to build
    echo   Check output above for details
    echo ================================================================================
    echo.
    pause
    exit /b 1
)

REM ============================================================================
REM  SUCCESS
REM ============================================================================
echo.
echo ================================================================================
echo   FULL PIPELINE WITH INSTALLERS COMPLETE
echo ================================================================================
echo.
echo   Outputs:
echo     - bin\*.vsix          (VSIX extension)
echo     - bin\*.nupkg         (NuGet CLI templates)
echo     - Installers\*.exe    (Addon installers)
echo.
echo   Reports:
echo     - _test\report.md
echo     - Docs\_audit\build-full-audit.md
echo.
pause
exit /b 0
