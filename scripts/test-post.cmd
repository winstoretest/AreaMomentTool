@echo off
REM ============================================================================
REM  Post-Build Template Validation
REM  Tests packaged templates after VSIX build
REM ============================================================================

cd /d "%~dp0"

echo.
echo  [POST-BUILD] Testing packaged templates...
echo.

REM Run full VSIX template tests
powershell -ExecutionPolicy Bypass -File "%~dp0Test-Templates.ps1" -TestVSIX

if errorlevel 1 (
    echo.
    echo  [POST-BUILD] FAILED - Template tests did not pass
    exit /b 1
)

echo.
echo  [POST-BUILD] PASSED
exit /b 0
