@echo off
REM ============================================================================
REM  Pre-Build Template Validation
REM  Validates source templates before building VSIX
REM ============================================================================

cd /d "%~dp0"
powershell -ExecutionPolicy Bypass -File "%~dp0Test-PreBuild.ps1"
exit /b %errorlevel%
