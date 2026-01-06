@echo off
REM ============================================================================
REM  Alibre Extensions Template Test Script
REM  Tests project and item templates outside of Visual Studio
REM ============================================================================

cd /d "%~dp0"

echo.
echo  Testing Alibre Extensions Templates...
echo.

REM Default: test VSIX templates (no dotnet new setup required)
if "%1"=="" (
    powershell -ExecutionPolicy Bypass -File "%~dp0Test-Templates.ps1" -TestVSIX -Clean
) else if "%1"=="vsix" (
    powershell -ExecutionPolicy Bypass -File "%~dp0Test-Templates.ps1" -TestVSIX -Clean
) else if "%1"=="nuget" (
    powershell -ExecutionPolicy Bypass -File "%~dp0Test-Templates.ps1" -TestNuGet -Clean
) else if "%1"=="all" (
    powershell -ExecutionPolicy Bypass -File "%~dp0Test-Templates.ps1" -TestVSIX -TestNuGet -Clean
) else (
    echo Usage: test.cmd [vsix^|nuget^|all]
    echo.
    echo   vsix   - Test VSIX templates (default)
    echo   nuget  - Test dotnet CLI templates
    echo   all    - Test both
    exit /b 1
)

if errorlevel 1 (
    echo.
    echo  Some tests failed!
    pause
    exit /b 1
)

echo.
echo  All tests passed!
pause
