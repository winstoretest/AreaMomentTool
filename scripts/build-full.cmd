@echo off
REM ============================================================================
REM  Full Build Pipeline with Pre/Post Testing
REM  Runs: test-pre -> build -> test-post
REM  Configuration loaded from build.config.json
REM ============================================================================

cd /d "%~dp0"

echo.
echo ================================================================================
echo   FULL BUILD PIPELINE
echo   (Configuration from build.config.json)
echo ================================================================================
echo.

REM ============================================================================
REM  STEP 1: Pre-Build Tests
REM ============================================================================
call "%~dp0test-pre.cmd"
if errorlevel 1 (
    echo.
    echo ================================================================================
    echo   PIPELINE ABORTED - Pre-build tests failed
    echo ================================================================================
    pause
    exit /b 1
)

REM ============================================================================
REM  STEP 2: Build VSIX and NuGet
REM ============================================================================
echo.
echo ================================================================================
echo   BUILDING VSIX AND NUGET PACKAGES
echo ================================================================================
call "%~dp0build.cmd"
if errorlevel 1 (
    echo.
    echo ================================================================================
    echo   PIPELINE ABORTED - Build failed
    echo ================================================================================
    pause
    exit /b 1
)

REM ============================================================================
REM  STEP 3: Post-Build Tests
REM ============================================================================
echo.
echo ================================================================================
echo   POST-BUILD TEMPLATE TESTS
echo ================================================================================
call "%~dp0test-post.cmd"
if errorlevel 1 (
    echo.
    echo ================================================================================
    echo   PIPELINE FAILED - Post-build tests failed
    echo ================================================================================
    pause
    exit /b 1
)

REM ============================================================================
REM  GENERATE PIPELINE AUDIT
REM ============================================================================
powershell -ExecutionPolicy Bypass -File "%~dp0Generate-PipelineAudit.ps1"

REM ============================================================================
REM  SUCCESS
REM ============================================================================
echo.
echo ================================================================================
echo   PIPELINE COMPLETE - All steps passed!
echo ================================================================================
echo.
echo   Outputs (see build.config.json for configured names):
echo     - bin\*.vsix (VSIX extension)
echo     - bin\*.nupkg (NuGet CLI templates)
echo     - _test\report.md
echo     - _test\audit.json
echo     - Docs\_audit\build-full-audit.md
echo.
pause
exit /b 0
