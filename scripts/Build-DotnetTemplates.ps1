<#
.SYNOPSIS
    Builds the NuGet package for dotnet CLI templates.

.DESCRIPTION
    This script creates a NuGet package (.nupkg) containing templates that can be
    installed via the 'dotnet new' command line interface.

    CLI templates provide an alternative to VSIX templates for developers who prefer
    command-line workflows or work on platforms without Visual Studio.

    The process:
    1. Validates template directories exist and have proper structure
    2. Downloads NuGet.exe if not present
    3. Runs 'nuget pack' to create the .nupkg file
    4. Optionally tests the package with 'dotnet new install'

    Template Structure Requirements:
    --------------------------------
    Each CLI template must have:
    - .template.config/template.json - Template configuration
    - Project file (.csproj or .vbproj)
    - Source files

    The template.json defines:
    - shortName: Command-line name (e.g., "alibre-addon-cs")
    - identity: Unique identifier
    - name: Display name
    - tags: Language and type tags

    NuGet Package Structure:
    ------------------------
    Alibre.Templates.nupkg
    └── content/
        ├── AlibreScriptAddonCS/
        │   ├── .template.config/template.json
        │   └── [template files]
        ├── AlibreSingleFileAddonCS/
        │   └── ...
        └── [other templates]

.PARAMETER OutputPath
    Directory where the .nupkg file will be created.
    Default: Templates/dotnet/packages/

.PARAMETER Version
    Version number for the NuGet package.
    Should follow SemVer (e.g., "1.0.0", "1.0.1-beta").
    If not specified, reads from nuspec file.

.PARAMETER TestInstall
    After building, test the package by installing it locally
    and listing the available templates.

.PARAMETER Clean
    Remove existing .nupkg files before building.

.EXAMPLE
    .\Build-DotnetTemplates.ps1

    Builds the NuGet package with default settings.

.EXAMPLE
    .\Build-DotnetTemplates.ps1 -Version "1.1.0" -TestInstall

    Builds version 1.1.0 and tests installation.

.EXAMPLE
    .\Build-DotnetTemplates.ps1 -Clean -TestInstall

    Clean build with installation test.

.NOTES
    Author: Stephen S. Mitchell
    Version: 1.0.0
    Date: December 2025

    Publishing to NuGet.org:
    -----------------------
    After building, publish with:
        nuget push Alibre.Templates.x.x.x.nupkg -Source https://api.nuget.org/v3/index.json -ApiKey YOUR_KEY

    Or via dotnet CLI:
        dotnet nuget push Alibre.Templates.x.x.x.nupkg --source https://api.nuget.org/v3/index.json --api-key YOUR_KEY

.LINK
    https://docs.microsoft.com/en-us/dotnet/core/tools/custom-templates
    https://github.com/Testbed-for-Alibre-Design/AlibreExtensions
#>

# ==============================================================================
# SCRIPT PARAMETERS
# ==============================================================================

[CmdletBinding()]
param(
    # Output directory for the NuGet package
    [string]$OutputPath,

    # Package version (overrides nuspec if specified)
    [string]$Version,

    # Test installation after building
    [switch]$TestInstall,

    # Clean existing packages before building
    [switch]$Clean
)

# ==============================================================================
# CONFIGURATION
# ==============================================================================

$ErrorActionPreference = "Stop"

# Script location and derived paths
$ScriptDir = $PSScriptRoot
$RootDir = (Resolve-Path (Join-Path $ScriptDir "..")).Path

# Templates directory structure
$Paths = @{
    # Root templates directory
    DotnetTemplates = Join-Path $RootDir "Templates\dotnet"

    # NuSpec file location
    NuSpec = Join-Path $RootDir "Templates\dotnet\Alibre.Templates.nuspec"

    # Output directory for packages
    Packages = if ($OutputPath) { $OutputPath } else { Join-Path $RootDir "Templates\dotnet\packages" }

    # Temp directory for downloads
    Temp = Join-Path $RootDir "_temp"
}

# List of template directories to verify
# Each must contain .template.config/template.json
$ExpectedTemplates = @(
    "AlibreScriptAddonCS",
    "AlibreScriptAddonVB",
    "AlibreSingleFileAddonCS",
    "AlibreSingleFileAddonCSRibbon",
    "AlibreSingleFileAddonVB",
    "AlibreSingleFileAddonVBRibbon"
)

# ==============================================================================
# HELPER FUNCTIONS
# ==============================================================================

function Write-Header {
    <#
    .SYNOPSIS
        Displays a formatted section header.
    #>
    param([string]$Text)

    $line = "=" * 60
    Write-Host ""
    Write-Host $line -ForegroundColor Cyan
    Write-Host "  $Text" -ForegroundColor Cyan
    Write-Host $line -ForegroundColor Cyan
    Write-Host ""
}

function Write-Step {
    param([string]$Text)
    Write-Host "  [*] $Text" -ForegroundColor White
}

function Write-Success {
    param([string]$Text)
    Write-Host "  [OK] $Text" -ForegroundColor Green
}

function Write-Failure {
    param([string]$Text)
    Write-Host "  [FAIL] $Text" -ForegroundColor Red
}

function Write-Info {
    param([string]$Text)
    Write-Host "  [i] $Text" -ForegroundColor Gray
}

function Get-NuGetExe {
    <#
    .SYNOPSIS
        Gets path to NuGet.exe, downloading if necessary.

    .DESCRIPTION
        First checks for NuGet.exe in the temp directory or PATH.
        If not found, downloads the latest version from nuget.org.

    .OUTPUTS
        Path to nuget.exe
    #>

    # Check temp directory first
    $nugetPath = Join-Path $Paths.Temp "nuget.exe"
    if (Test-Path $nugetPath) {
        return $nugetPath
    }

    # Check PATH
    $nugetInPath = Get-Command nuget.exe -ErrorAction SilentlyContinue
    if ($nugetInPath) {
        return $nugetInPath.Path
    }

    # Download NuGet.exe
    Write-Step "Downloading NuGet.exe..."

    # Ensure temp directory exists
    if (-not (Test-Path $Paths.Temp)) {
        New-Item -ItemType Directory -Path $Paths.Temp -Force | Out-Null
    }

    try {
        $downloadUrl = "https://dist.nuget.org/win-x86-commandline/latest/nuget.exe"
        Invoke-WebRequest -Uri $downloadUrl -OutFile $nugetPath -UseBasicParsing
        Write-Success "Downloaded NuGet.exe"
        return $nugetPath
    }
    catch {
        throw "Failed to download NuGet.exe: $_"
    }
}

function Test-TemplateStructure {
    <#
    .SYNOPSIS
        Validates that a template directory has correct structure.

    .DESCRIPTION
        Checks for:
        - .template.config/template.json exists
        - template.json is valid JSON
        - Required properties are present

    .PARAMETER TemplatePath
        Path to the template directory.

    .OUTPUTS
        $true if valid, $false otherwise.
    #>
    param([string]$TemplatePath)

    $configPath = Join-Path $TemplatePath ".template.config\template.json"

    # Check template.json exists
    if (-not (Test-Path $configPath)) {
        Write-Warning "Missing: $configPath"
        return $false
    }

    # Validate JSON
    try {
        $config = Get-Content $configPath -Raw | ConvertFrom-Json

        # Check required properties
        $requiredProps = @("identity", "shortName", "name", "tags")
        foreach ($prop in $requiredProps) {
            if (-not $config.$prop) {
                Write-Warning "Missing property '$prop' in $configPath"
                return $false
            }
        }

        return $true
    }
    catch {
        Write-Warning "Invalid JSON in $configPath : $_"
        return $false
    }
}

function Get-NuSpecVersion {
    <#
    .SYNOPSIS
        Reads the version from the nuspec file.

    .OUTPUTS
        Version string from nuspec.
    #>

    if (-not (Test-Path $Paths.NuSpec)) {
        throw "NuSpec file not found: $($Paths.NuSpec)"
    }

    [xml]$nuspec = Get-Content $Paths.NuSpec
    return $nuspec.package.metadata.version
}

function Update-NuSpecVersion {
    <#
    .SYNOPSIS
        Updates the version in the nuspec file.

    .PARAMETER NewVersion
        New version string.
    #>
    param([string]$NewVersion)

    [xml]$nuspec = Get-Content $Paths.NuSpec
    $nuspec.package.metadata.version = $NewVersion

    # Save with proper formatting
    $settings = New-Object System.Xml.XmlWriterSettings
    $settings.Indent = $true
    $settings.IndentChars = "  "
    $settings.Encoding = [System.Text.Encoding]::UTF8

    $writer = [System.Xml.XmlWriter]::Create($Paths.NuSpec, $settings)
    $nuspec.Save($writer)
    $writer.Close()
}

# ==============================================================================
# MAIN EXECUTION
# ==============================================================================

Write-Header "Building .NET CLI Templates Package"

# ---------------------------------------------------------------------------
# STEP 1: Validate environment
# ---------------------------------------------------------------------------

Write-Step "Validating environment..."

# Check dotnet CLI is available
$dotnetVersion = dotnet --version 2>$null
if (-not $dotnetVersion) {
    throw ".NET SDK is not installed or not in PATH"
}
Write-Info ".NET SDK version: $dotnetVersion"

# Check templates directory exists
if (-not (Test-Path $Paths.DotnetTemplates)) {
    throw "Templates directory not found: $($Paths.DotnetTemplates)"
}
Write-Info "Templates directory: $($Paths.DotnetTemplates)"

# Check nuspec exists
if (-not (Test-Path $Paths.NuSpec)) {
    throw "NuSpec file not found: $($Paths.NuSpec)"
}
Write-Info "NuSpec file: $($Paths.NuSpec)"

Write-Success "Environment validated"
Write-Host ""

# ---------------------------------------------------------------------------
# STEP 2: Validate template structure
# ---------------------------------------------------------------------------

Write-Step "Validating template structure..."

$validTemplates = 0
$invalidTemplates = 0

foreach ($templateName in $ExpectedTemplates) {
    $templatePath = Join-Path $Paths.DotnetTemplates $templateName

    if (-not (Test-Path $templatePath)) {
        Write-Warning "Template directory missing: $templateName"
        $invalidTemplates++
        continue
    }

    if (Test-TemplateStructure -TemplatePath $templatePath) {
        Write-Info "Valid: $templateName"
        $validTemplates++
    } else {
        $invalidTemplates++
    }
}

if ($validTemplates -eq 0) {
    throw "No valid templates found. Cannot create package."
}

Write-Success "$validTemplates valid template(s), $invalidTemplates invalid"
Write-Host ""

# ---------------------------------------------------------------------------
# STEP 3: Handle version
# ---------------------------------------------------------------------------

$currentVersion = Get-NuSpecVersion
Write-Info "Current version in nuspec: $currentVersion"

if ($Version) {
    if ($Version -ne $currentVersion) {
        Write-Step "Updating version to $Version..."
        Update-NuSpecVersion -NewVersion $Version
        Write-Success "Version updated"
    }
    $packageVersion = $Version
} else {
    $packageVersion = $currentVersion
}
Write-Host ""

# ---------------------------------------------------------------------------
# STEP 4: Clean existing packages (if requested)
# ---------------------------------------------------------------------------

# Ensure output directory exists
if (-not (Test-Path $Paths.Packages)) {
    New-Item -ItemType Directory -Path $Paths.Packages -Force | Out-Null
    Write-Info "Created output directory: $($Paths.Packages)"
}

if ($Clean) {
    Write-Step "Cleaning existing packages..."
    $existingPackages = Get-ChildItem -Path $Paths.Packages -Filter "*.nupkg" -ErrorAction SilentlyContinue
    foreach ($pkg in $existingPackages) {
        Remove-Item $pkg.FullName -Force
        Write-Info "Removed: $($pkg.Name)"
    }
    Write-Success "Clean completed"
    Write-Host ""
}

# ---------------------------------------------------------------------------
# STEP 5: Get NuGet.exe
# ---------------------------------------------------------------------------

$nugetExe = Get-NuGetExe
Write-Info "Using NuGet: $nugetExe"
Write-Host ""

# ---------------------------------------------------------------------------
# STEP 6: Create NuGet package
# ---------------------------------------------------------------------------

Write-Step "Creating NuGet package..."

# Change to templates directory for nuget pack
Push-Location $Paths.DotnetTemplates
try {
    # Run nuget pack
    $nugetArgs = @(
        "pack",
        $Paths.NuSpec,
        "-OutputDirectory", $Paths.Packages,
        "-NoPackageAnalysis"  # Skip analysis for template packages
    )

    if ($Version) {
        $nugetArgs += "-Version"
        $nugetArgs += $Version
    }

    Write-Host ""
    & $nugetExe @nugetArgs
    $exitCode = $LASTEXITCODE
}
finally {
    Pop-Location
}

Write-Host ""

if ($exitCode -ne 0) {
    throw "NuGet pack failed with exit code: $exitCode"
}

# Find the created package
$packagePattern = "Alibre.Templates.$packageVersion.nupkg"
$createdPackage = Get-ChildItem -Path $Paths.Packages -Filter $packagePattern | Select-Object -First 1

if (-not $createdPackage) {
    # Try wildcard if exact version not found
    $createdPackage = Get-ChildItem -Path $Paths.Packages -Filter "Alibre.Templates.*.nupkg" |
                      Sort-Object LastWriteTime -Descending |
                      Select-Object -First 1
}

if ($createdPackage) {
    $packageSize = [math]::Round($createdPackage.Length / 1KB, 2)
    Write-Success "Package created: $($createdPackage.Name) ($packageSize KB)"
    Write-Info "Location: $($createdPackage.FullName)"
} else {
    throw "Package file not found after build"
}

Write-Host ""

# ---------------------------------------------------------------------------
# STEP 7: Test installation (if requested)
# ---------------------------------------------------------------------------

if ($TestInstall) {
    Write-Header "Testing Package Installation"

    Write-Step "Uninstalling any existing version..."
    try {
        dotnet new uninstall Alibre.Templates 2>$null | Out-Null
    } catch {
        # Ignore errors - package might not be installed
    }
    Write-Success "Uninstall completed (or was not installed)"
    Write-Host ""

    Write-Step "Installing from local package..."
    dotnet new install $createdPackage.FullName
    Write-Host ""

    Write-Step "Listing installed Alibre templates..."
    Write-Host ""
    dotnet new list alibre
    Write-Host ""

    Write-Success "Test installation completed"
    Write-Host ""

    # Provide usage examples
    Write-Info "To create a new project:"
    Write-Host "    dotnet new alibre-addon-cs -n MyAddOn" -ForegroundColor White
    Write-Host "    dotnet new alibre-addon-vb -n MyAddOn" -ForegroundColor White
    Write-Host "    dotnet new alibre-script-cs -n MyScriptAddOn" -ForegroundColor White
    Write-Host ""

    Write-Info "To uninstall:"
    Write-Host "    dotnet new uninstall Alibre.Templates" -ForegroundColor White
}

# ---------------------------------------------------------------------------
# SUMMARY
# ---------------------------------------------------------------------------

Write-Host ""
Write-Host "============================================================" -ForegroundColor Cyan
Write-Host "  BUILD COMPLETE" -ForegroundColor Cyan
Write-Host "============================================================" -ForegroundColor Cyan
Write-Host ""
Write-Host "  Package: $($createdPackage.Name)" -ForegroundColor White
Write-Host "  Version: $packageVersion" -ForegroundColor White
Write-Host "  Templates: $validTemplates" -ForegroundColor White
Write-Host ""
Write-Host "  To publish to NuGet.org:" -ForegroundColor Gray
Write-Host "    nuget push $($createdPackage.FullName) -Source https://api.nuget.org/v3/index.json -ApiKey YOUR_KEY" -ForegroundColor White
Write-Host ""
