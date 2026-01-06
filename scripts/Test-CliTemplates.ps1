<#
.SYNOPSIS
    Tests the Alibre Design CLI templates by installing, creating projects, and building.

.DESCRIPTION
    This script:
    1. Installs the AlibreDesign.Templates NuGet package
    2. Creates all 6 project types from the templates
    3. Adds them to a solution
    4. Builds all projects

.PARAMETER NuPkgPath
    Path to the .nupkg file. If not specified, installs from NuGet.org.

.PARAMETER OutputDir
    Directory to create test projects. Defaults to a temp directory.

.PARAMETER SkipInstall
    Skip template installation (use if already installed).

.PARAMETER Cleanup
    Remove the output directory after testing.

.EXAMPLE
    .\Test-CliTemplates.ps1

    Installs templates from NuGet.org and tests all project types.

.EXAMPLE
    .\Test-CliTemplates.ps1 -NuPkgPath ".\bin\AlibreDesign.Templates.1.0.0.nupkg"

    Installs from local package and tests.
#>

param(
    [string]$NuPkgPath,
    [string]$OutputDir,
    [switch]$SkipInstall,
    [switch]$Cleanup
)

$ErrorActionPreference = "Stop"

# Banner
Write-Host ""
Write-Host "================================================================================" -ForegroundColor Cyan
Write-Host "  ALIBRE DESIGN CLI TEMPLATE TEST" -ForegroundColor Cyan
Write-Host "================================================================================" -ForegroundColor Cyan
Write-Host ""

# Setup output directory
if (-not $OutputDir) {
    $OutputDir = Join-Path ([System.IO.Path]::GetTempPath()) "AlibreTemplateTest_$(Get-Date -Format 'yyyyMMdd_HHmmss')"
}

Write-Host "[1/5] Setting up test directory..." -ForegroundColor Yellow
Write-Host "      Output: $OutputDir"
if (-not (Test-Path $OutputDir)) {
    New-Item -ItemType Directory -Path $OutputDir -Force | Out-Null
}

# Install templates
if (-not $SkipInstall) {
    Write-Host ""
    Write-Host "[2/5] Installing templates..." -ForegroundColor Yellow

    # Uninstall first if exists
    Write-Host "      Uninstalling existing templates (if any)..."
    dotnet new uninstall AlibreDesign.Templates 2>$null | Out-Null

    if ($NuPkgPath) {
        Write-Host "      Installing from: $NuPkgPath"
        dotnet new install $NuPkgPath
    } else {
        Write-Host "      Installing from NuGet.org..."
        dotnet new install AlibreDesign.Templates
    }

    if ($LASTEXITCODE -ne 0) {
        Write-Host "      [FAIL] Template installation failed!" -ForegroundColor Red
        exit 1
    }
    Write-Host "      [OK] Templates installed" -ForegroundColor Green
} else {
    Write-Host ""
    Write-Host "[2/5] Skipping template installation (--SkipInstall)" -ForegroundColor Yellow
}

# List available templates
Write-Host ""
Write-Host "[3/5] Creating projects from templates..." -ForegroundColor Yellow
Write-Host ""

# Define the 6 project types to create
$projects = @(
    @{ Name = "TestScriptAddonCS";      Template = "alibre-script-cs";      Lang = "C#" },
    @{ Name = "TestScriptAddonVB";      Template = "alibre-script-vb";      Lang = "VB" },
    @{ Name = "TestSingleFileCS";       Template = "alibre-addon-cs";       Lang = "C#" },
    @{ Name = "TestSingleFileVB";       Template = "alibre-addon-vb";       Lang = "VB" },
    @{ Name = "TestRibbonCS";           Template = "alibre-ribbon-cs";      Lang = "C#" },
    @{ Name = "TestRibbonVB";           Template = "alibre-ribbon-vb";      Lang = "VB" }
)

$createdProjects = @()

foreach ($proj in $projects) {
    $projPath = Join-Path $OutputDir $proj.Name
    Write-Host "      Creating: $($proj.Name) [$($proj.Lang)]..."

    dotnet new $proj.Template -n $proj.Name -o $projPath 2>&1 | Out-Null

    if ($LASTEXITCODE -eq 0) {
        Write-Host "        [OK] Created" -ForegroundColor Green
        $createdProjects += @{
            Name = $proj.Name
            Path = $projPath
            Lang = $proj.Lang
        }
    } else {
        Write-Host "        [FAIL] Failed to create $($proj.Name)" -ForegroundColor Red
    }
}

# Create solution and add projects
Write-Host ""
Write-Host "[4/5] Creating solution and adding projects..." -ForegroundColor Yellow

$slnPath = Join-Path $OutputDir "AlibreTemplateTest.sln"
dotnet new sln -n "AlibreTemplateTest" -o $OutputDir 2>&1 | Out-Null

foreach ($proj in $createdProjects) {
    # Find the .csproj or .vbproj file
    $projFile = Get-ChildItem -Path $proj.Path -Recurse -Include "*.csproj", "*.vbproj" | Select-Object -First 1
    if ($projFile) {
        Write-Host "      Adding: $($proj.Name)..."
        dotnet sln $slnPath add $projFile.FullName 2>&1 | Out-Null
        if ($LASTEXITCODE -eq 0) {
            Write-Host "        [OK] Added to solution" -ForegroundColor Green
        } else {
            Write-Host "        [WARN] Could not add to solution" -ForegroundColor Yellow
        }
    }
}

# Build all projects
Write-Host ""
Write-Host "[5/5] Building solution..." -ForegroundColor Yellow
Write-Host ""

Push-Location $OutputDir
try {
    dotnet restore $slnPath
    $buildResult = dotnet build $slnPath --configuration Release 2>&1
    $buildExitCode = $LASTEXITCODE

    if ($buildExitCode -eq 0) {
        Write-Host ""
        Write-Host "      [OK] Build succeeded!" -ForegroundColor Green
    } else {
        Write-Host ""
        Write-Host "      [FAIL] Build failed!" -ForegroundColor Red
        Write-Host $buildResult
    }
} finally {
    Pop-Location
}

# Summary
Write-Host ""
Write-Host "================================================================================" -ForegroundColor Cyan
Write-Host "  TEST SUMMARY" -ForegroundColor Cyan
Write-Host "================================================================================" -ForegroundColor Cyan
Write-Host ""
Write-Host "  Projects created: $($createdProjects.Count) / $($projects.Count)"
Write-Host "  Solution: $slnPath"
Write-Host "  Build: $(if ($buildExitCode -eq 0) { 'PASSED' } else { 'FAILED' })"
Write-Host ""

if ($Cleanup -and $buildExitCode -eq 0) {
    Write-Host "  Cleaning up test directory..."
    Remove-Item $OutputDir -Recurse -Force
    Write-Host "  [OK] Cleaned up" -ForegroundColor Green
} else {
    Write-Host "  Test output: $OutputDir"
}

Write-Host ""

# Return exit code
exit $buildExitCode
