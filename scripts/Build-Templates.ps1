<#
.SYNOPSIS
    Master build script for Alibre Design Visual Studio Extension templates.

.DESCRIPTION
    This is the main orchestration script that automates the complete build process
    for both VSIX (Visual Studio Extension) and NuGet (CLI) templates.

    The script performs the following operations:
    1. Scans the Working/ directory for source template projects
    2. Generates .vstemplate files with proper metadata
    3. Packages templates into ZIP files for VSIX
    4. Updates the VSIX project file with template references
    5. Optionally builds the VSIX extension
    6. Optionally builds the NuGet package for CLI templates

    This script coordinates calls to other specialized scripts:
    - New-VSTemplate.ps1: Generates .vstemplate XML files
    - New-TemplateZip.ps1: Creates ZIP packages
    - Build-DotnetTemplates.ps1: Builds NuGet packages

.PARAMETER Clean
    Remove all existing template packages before building.
    Use this when you want a fresh build with no leftover artifacts.

.PARAMETER BuildVSIX
    Build the VSIX extension after packaging templates.
    The VSIX file will be created in Extension/VSExtensionForAlibreVB/bin/

.PARAMETER BuildNuGet
    Build the NuGet package for dotnet CLI templates.
    The .nupkg file will be created in Templates/dotnet/

.PARAMETER Configuration
    MSBuild configuration: Debug or Release. Default is Release.
    Debug builds include additional debugging symbols.

.PARAMETER TemplateFilter
    Optional filter to build only specific templates.
    Accepts wildcards. Example: "*CS*" builds only C# templates.

.PARAMETER Verbose
    Show detailed output during the build process.

.EXAMPLE
    .\Build-Templates.ps1

    Basic build - packages all templates without building VSIX or NuGet.

.EXAMPLE
    .\Build-Templates.ps1 -Clean -BuildVSIX -BuildNuGet

    Full clean build of everything - VSIX and NuGet packages.

.EXAMPLE
    .\Build-Templates.ps1 -BuildVSIX -Configuration Debug

    Build VSIX in Debug mode for testing.

.EXAMPLE
    .\Build-Templates.ps1 -TemplateFilter "*VB*"

    Build only VB.NET templates.

.NOTES
    Author: Stephen S. Mitchell
    Version: 1.0.0
    Date: December 2025

    Prerequisites:
    - Visual Studio 2022 or 2026 with VSIX tools
    - PowerShell 5.1 or later
    - NuGet.exe (auto-downloaded if missing)

.LINK
    https://github.com/Testbed-for-Alibre-Design/AlibreExtensions
#>

# ==============================================================================
# SCRIPT PARAMETERS
# ==============================================================================
# These parameters control the build behavior and can be passed from command line

[CmdletBinding()]
param(
    # When set, removes all existing template ZIPs before building
    [switch]$Clean,

    # When set, builds the VSIX extension package
    [switch]$BuildVSIX,

    # When set, builds the NuGet package for CLI templates
    [switch]$BuildNuGet,

    # MSBuild configuration (Debug includes symbols, Release is optimized)
    [ValidateSet("Debug", "Release")]
    [string]$Configuration = "Release",

    # Optional filter to build specific templates (supports wildcards)
    [string]$TemplateFilter = "*"
)

# ==============================================================================
# SCRIPT CONFIGURATION
# ==============================================================================
# Stop on any error to prevent partial/corrupt builds
$ErrorActionPreference = "Stop"

# Get the directory where this script is located
# All paths are relative to this location for portability
$ScriptDir = $PSScriptRoot

# Define all important paths relative to the script location
# This structure keeps the project organized and maintainable
$Paths = @{
    # Root of the entire project (one level up from Scripts/)
    Root = (Resolve-Path (Join-Path $ScriptDir "..")).Path

    # Working directory contains the source template projects
    # Each subdirectory here is a potential template
    Working = Join-Path (Resolve-Path (Join-Path $ScriptDir "..")).Path "Working\Projects"

    # Extension directory contains the VSIX project
    Extension = Join-Path (Resolve-Path (Join-Path $ScriptDir "..")).Path "Extension\VSExtensionForAlibreDesign"

    # ProjectTemplates is where VSIX expects the template ZIPs
    ProjectTemplates = Join-Path (Resolve-Path (Join-Path $ScriptDir "..")).Path "Extension\VSExtensionForAlibreDesign\ProjectTemplates"

    # CLI templates for dotnet new
    DotnetTemplates = Join-Path (Resolve-Path (Join-Path $ScriptDir "..")).Path "Templates\dotnet"

    # Temporary directory for build operations
    Temp = Join-Path (Resolve-Path (Join-Path $ScriptDir "..")).Path "_temp"
}

# ==============================================================================
# TEMPLATE DEFINITIONS
# ==============================================================================
# This is the master list of all templates to build.
# Each template definition contains all metadata needed for both VSIX and CLI.
#
# To add a new template:
# 1. Create the source project in Working/[TemplateName]/
# 2. Add a new entry to this array with all required properties
# 3. Run this script to generate the template
#
# Properties explained:
#   SourceFolder    - Name of folder in Working/ containing source files
#   ZipName         - Name for the output ZIP file (without .zip extension)
#   DisplayName     - Name shown in Visual Studio "New Project" dialog
#   Description     - Detailed description for VS and NuGet
#   Language        - "CSharp" or "VisualBasic"
#   DefaultName     - Default project name when user creates new project
#   SortOrder       - Order in VS template list (lower = higher in list)
#   ShortName       - Short name for dotnet CLI (e.g., "alibre-addon-cs")
#   CliIdentity     - Unique identifier for CLI template
#   Tags            - Array of tags for discoverability

$TemplateDefinitions = @(
    # -------------------------------------------------------------------------
    # C# TEMPLATES
    # -------------------------------------------------------------------------
    @{
        SourceFolder = "AlibreScriptAddonCS"
        ZipName = "AlibreScriptAddonCS"
        DisplayName = "Alibre Script AddOn (C#)"
        Description = "C# Alibre Design AddOn with IronPython scripting support. Run Python scripts from your AddOn menu. Includes sample scripts and setup utilities. Targets .NET Framework 4.8.1."
        Language = "CSharp"
        DefaultName = "AlibreScriptAddon"
        SortOrder = 100
        ShortName = "alibre-script-cs"
        CliIdentity = "Alibre.ScriptAddOn.CSharp"
        Tags = @("Alibre", "CAD", "AddOn", "Script", "IronPython")
    },
    @{
        SourceFolder = "AlibreSingleFileAddonCS"
        ZipName = "AlibreSingleFileAddonCS"
        DisplayName = "Alibre Single File AddOn (C#)"
        Description = "Minimal C# Alibre Design AddOn for quick menu-based extensions. Includes example code showing menu commands and session handling. Perfect for simple automation tasks. Targets .NET Framework 4.8.1."
        Language = "CSharp"
        DefaultName = "AlibreAddon"
        SortOrder = 102
        ShortName = "alibre-addon-cs"
        CliIdentity = "Alibre.SingleFileAddOn.CSharp"
        Tags = @("Alibre", "CAD", "AddOn")
    },
    @{
        SourceFolder = "AlibreSingleFileAddonCSRibbon"
        ZipName = "AlibreSingleFileAddonCSRibbon"
        DisplayName = "Alibre Single File AddOn with Ribbon (C#)"
        Description = "C# Alibre Design AddOn with ribbon UI integration. Create professional ribbon-based extensions with custom tabs and buttons. Includes example code for ribbon commands. Targets .NET Framework 4.8.1."
        Language = "CSharp"
        DefaultName = "AlibreRibbonAddon"
        SortOrder = 103
        ShortName = "alibre-ribbon-cs"
        CliIdentity = "Alibre.SingleFileRibbonAddOn.CSharp"
        Tags = @("Alibre", "CAD", "AddOn", "Ribbon", "UI")
    },

    # -------------------------------------------------------------------------
    # VB.NET TEMPLATES
    # -------------------------------------------------------------------------
    @{
        SourceFolder = "AlibreScriptAddonVB"
        ZipName = "AlibreScriptAddonVB"
        DisplayName = "Alibre Script AddOn (VB.NET)"
        Description = "VB.NET Alibre Design AddOn with IronPython scripting support. Run Python scripts from your AddOn menu. Includes sample scripts and setup utilities. Targets .NET Framework 4.8.1."
        Language = "VisualBasic"
        DefaultName = "AlibreScriptAddon"
        SortOrder = 101
        ShortName = "alibre-script-vb"
        CliIdentity = "Alibre.ScriptAddOn.VB"
        Tags = @("Alibre", "CAD", "AddOn", "Script", "IronPython")
    },
    @{
        SourceFolder = "AlibreSingleFileAddonVB"
        ZipName = "AlibreSingleFileAddonVB"
        DisplayName = "Alibre Single File AddOn (VB.NET)"
        Description = "Minimal VB.NET Alibre Design AddOn for quick menu-based extensions. Includes example code showing menu commands and session handling. Perfect for simple automation tasks. Targets .NET Framework 4.8.1."
        Language = "VisualBasic"
        DefaultName = "AlibreAddon"
        SortOrder = 104
        ShortName = "alibre-addon-vb"
        CliIdentity = "Alibre.SingleFileAddOn.VB"
        Tags = @("Alibre", "CAD", "AddOn")
    },
    @{
        SourceFolder = "AlibreSingleFileAddonVBRibbon"
        ZipName = "AlibreSingleFileAddonVBRibbon"
        DisplayName = "Alibre Single File AddOn with Ribbon (VB.NET)"
        Description = "VB.NET Alibre Design AddOn with ribbon UI integration. Create professional ribbon-based extensions with custom tabs and buttons. Includes example code for ribbon commands. Targets .NET Framework 4.8.1."
        Language = "VisualBasic"
        DefaultName = "AlibreRibbonAddon"
        SortOrder = 105
        ShortName = "alibre-ribbon-vb"
        CliIdentity = "Alibre.SingleFileRibbonAddOn.VB"
        Tags = @("Alibre", "CAD", "AddOn", "Ribbon", "UI")
    }
)

# ==============================================================================
# MSBUILD DISCOVERY
# ==============================================================================
# Find MSBuild.exe for building the VSIX project.
# We search for VS 2026 first, then fall back to VS 2022.
# This ensures we use the newest available tooling.

function Find-MSBuild {
    <#
    .SYNOPSIS
        Locates MSBuild.exe on the system.

    .DESCRIPTION
        Searches for MSBuild in standard Visual Studio installation locations.
        Prioritizes VS 2026 (version 18) over VS 2022 (version 17).
        Returns the full path to MSBuild.exe or $null if not found.
    #>

    # Define search paths in priority order (newest VS first)
    $searchPaths = @(
        # Visual Studio 2026 (version 18) - various editions
        "C:\Program Files\Microsoft Visual Studio\2026\Enterprise\MSBuild\Current\Bin\amd64\MSBuild.exe",
        "C:\Program Files\Microsoft Visual Studio\2026\Professional\MSBuild\Current\Bin\amd64\MSBuild.exe",
        "C:\Program Files\Microsoft Visual Studio\2026\Community\MSBuild\Current\Bin\amd64\MSBuild.exe",
        "C:\Program Files\Microsoft Visual Studio\2026\Preview\MSBuild\Current\Bin\amd64\MSBuild.exe",
        # VS 2026 Insiders uses version 18 internally
        "C:\Program Files\Microsoft Visual Studio\18\Enterprise\MSBuild\Current\Bin\amd64\MSBuild.exe",
        "C:\Program Files\Microsoft Visual Studio\18\Professional\MSBuild\Current\Bin\amd64\MSBuild.exe",
        "C:\Program Files\Microsoft Visual Studio\18\Community\MSBuild\Current\Bin\amd64\MSBuild.exe",
        "C:\Program Files\Microsoft Visual Studio\18\Insiders\MSBuild\Current\Bin\amd64\MSBuild.exe",
        "C:\Program Files\Microsoft Visual Studio\18\Preview\MSBuild\Current\Bin\amd64\MSBuild.exe",
        # Visual Studio 2022 (version 17) - fallback
        "C:\Program Files\Microsoft Visual Studio\2022\Enterprise\MSBuild\Current\Bin\amd64\MSBuild.exe",
        "C:\Program Files\Microsoft Visual Studio\2022\Professional\MSBuild\Current\Bin\amd64\MSBuild.exe",
        "C:\Program Files\Microsoft Visual Studio\2022\Community\MSBuild\Current\Bin\amd64\MSBuild.exe",
        "C:\Program Files\Microsoft Visual Studio\2022\Preview\MSBuild\Current\Bin\amd64\MSBuild.exe"
    )

    # Return the first path that exists
    foreach ($path in $searchPaths) {
        if (Test-Path $path) {
            return $path
        }
    }

    # Try vswhere as a last resort (finds any VS installation)
    $vswhere = "${env:ProgramFiles(x86)}\Microsoft Visual Studio\Installer\vswhere.exe"
    if (Test-Path $vswhere) {
        $vsPath = & $vswhere -latest -requires Microsoft.Component.MSBuild -find MSBuild\**\Bin\amd64\MSBuild.exe | Select-Object -First 1
        if ($vsPath -and (Test-Path $vsPath)) {
            return $vsPath
        }
    }

    return $null
}

# ==============================================================================
# HELPER FUNCTIONS
# ==============================================================================

function Write-Header {
    <#
    .SYNOPSIS
        Displays a formatted header in the console output.

    .DESCRIPTION
        Creates a visually distinct section header to help users
        understand what phase of the build process is running.

    .PARAMETER Text
        The header text to display.
    #>
    param([string]$Text)

    $line = "=" * 60
    Write-Host ""
    Write-Host $line -ForegroundColor Yellow
    Write-Host "  $Text" -ForegroundColor Yellow
    Write-Host $line -ForegroundColor Yellow
    Write-Host ""
}

function Write-Step {
    <#
    .SYNOPSIS
        Displays a build step message.

    .PARAMETER Text
        The step description to display.
    #>
    param([string]$Text)

    Write-Host "  [*] $Text" -ForegroundColor Cyan
}

function Write-Success {
    <#
    .SYNOPSIS
        Displays a success message.

    .PARAMETER Text
        The success message to display.
    #>
    param([string]$Text)

    Write-Host "  [OK] $Text" -ForegroundColor Green
}

function Write-Failure {
    <#
    .SYNOPSIS
        Displays a failure message.

    .PARAMETER Text
        The failure message to display.
    #>
    param([string]$Text)

    Write-Host "  [FAIL] $Text" -ForegroundColor Red
}

function Write-Info {
    <#
    .SYNOPSIS
        Displays an informational message.

    .PARAMETER Text
        The info message to display.
    #>
    param([string]$Text)

    Write-Host "  [i] $Text" -ForegroundColor Gray
}

# ==============================================================================
# MAIN BUILD FUNCTIONS
# ==============================================================================

function Initialize-BuildEnvironment {
    <#
    .SYNOPSIS
        Prepares the build environment.

    .DESCRIPTION
        Creates necessary directories, cleans old artifacts if requested,
        and validates that required paths exist.
    #>

    Write-Header "Initializing Build Environment"

    # Verify Working directory exists
    if (-not (Test-Path $Paths.Working)) {
        throw "Working directory not found: $($Paths.Working)"
    }
    Write-Info "Working directory: $($Paths.Working)"

    # Create temp directory
    if (-not (Test-Path $Paths.Temp)) {
        New-Item -ItemType Directory -Path $Paths.Temp -Force | Out-Null
        Write-Info "Created temp directory: $($Paths.Temp)"
    }

    # Create ProjectTemplates directory if needed
    if (-not (Test-Path $Paths.ProjectTemplates)) {
        New-Item -ItemType Directory -Path $Paths.ProjectTemplates -Force | Out-Null
        Write-Info "Created ProjectTemplates directory"
    }

    # Clean existing templates if requested
    if ($Clean) {
        Write-Step "Cleaning existing template packages..."

        $existingZips = Get-ChildItem -Path $Paths.ProjectTemplates -Filter "*.zip" -ErrorAction SilentlyContinue
        foreach ($zip in $existingZips) {
            Remove-Item $zip.FullName -Force
            Write-Info "Removed: $($zip.Name)"
        }

        # Also clean temp directory
        if (Test-Path $Paths.Temp) {
            Remove-Item $Paths.Temp -Recurse -Force
            New-Item -ItemType Directory -Path $Paths.Temp -Force | Out-Null
        }

        Write-Success "Clean completed"
    }
}

function Build-SingleTemplate {
    <#
    .SYNOPSIS
        Builds a single template from source.

    .DESCRIPTION
        Takes a template definition, generates the .vstemplate file,
        and packages everything into a ZIP file.

    .PARAMETER Definition
        Hashtable containing template metadata (from $TemplateDefinitions).

    .OUTPUTS
        Returns $true if successful, $false otherwise.
    #>
    param(
        [Parameter(Mandatory)]
        [hashtable]$Definition
    )

    $templateName = $Definition.DisplayName
    Write-Step "Building: $templateName"

    # Locate source directory
    $sourcePath = Join-Path $Paths.Working $Definition.SourceFolder
    if (-not (Test-Path $sourcePath)) {
        Write-Failure "Source not found: $sourcePath"
        return $false
    }

    # Create staging directory for this template
    $stagingPath = Join-Path $Paths.Temp $Definition.ZipName
    if (Test-Path $stagingPath) {
        Remove-Item $stagingPath -Recurse -Force
    }
    New-Item -ItemType Directory -Path $stagingPath -Force | Out-Null

    # ---------------------------------------------------------------------------
    # STEP 1: Copy source files to staging
    # ---------------------------------------------------------------------------
    # We copy all source files except build artifacts (bin, obj, .vs, etc.)
    # These files will become part of the template package

    Write-Info "Copying source files..."

    # Define patterns to exclude from template
    # These are files/folders that shouldn't be in the template package
    $excludePatterns = @(
        "bin",           # Build output
        "obj",           # Intermediate build files
        ".vs",           # Visual Studio settings
        ".git",          # Git repository data
        "*.user",        # User-specific VS settings
        "*.suo",         # Solution user options (legacy)
        "*.log",         # Log files
        "packages",      # NuGet packages folder
        "TestResults",   # Test output
        ".template.config"  # CLI template config (handled separately)
    )

    # Copy files recursively, excluding unwanted patterns
    $sourceFiles = Get-ChildItem -Path $sourcePath -Recurse -File | Where-Object {
        $relativePath = $_.FullName.Substring($sourcePath.Length + 1)
        $exclude = $false
        foreach ($pattern in $excludePatterns) {
            if ($relativePath -like "*$pattern*") {
                $exclude = $true
                break
            }
        }
        -not $exclude
    }

    foreach ($file in $sourceFiles) {
        # Calculate relative path and destination
        $relativePath = $file.FullName.Substring($sourcePath.Length + 1)
        $destPath = Join-Path $stagingPath $relativePath
        $destDir = Split-Path $destPath -Parent

        # Create destination directory if needed
        if (-not (Test-Path $destDir)) {
            New-Item -ItemType Directory -Path $destDir -Force | Out-Null
        }

        # Copy the file
        Copy-Item $file.FullName -Destination $destPath -Force
    }

    $fileCount = $sourceFiles.Count
    Write-Info "Copied $fileCount files"

    # ---------------------------------------------------------------------------
    # STEP 2: Generate .vstemplate file
    # ---------------------------------------------------------------------------
    # The .vstemplate file tells Visual Studio how to create projects from this template.
    # It contains metadata (name, description) and a list of all files to include.

    Write-Info "Generating .vstemplate..."

    # Call the vstemplate generator script
    $vstemplateScript = Join-Path $ScriptDir "New-VSTemplate.ps1"
    if (Test-Path $vstemplateScript) {
        & $vstemplateScript `
            -SourcePath $stagingPath `
            -TemplateName $Definition.DisplayName `
            -Description $Definition.Description `
            -Language $Definition.Language `
            -DefaultName $Definition.DefaultName `
            -SortOrder $Definition.SortOrder `
            -TemplateID $Definition.ZipName
    } else {
        # Inline vstemplate generation if script not available
        $vstemplateContent = Generate-VSTemplateXml -Definition $Definition -StagingPath $stagingPath
        $vstemplateFile = Join-Path $stagingPath "MyTemplate.vstemplate"
        $vstemplateContent | Out-File -FilePath $vstemplateFile -Encoding UTF8
    }

    # ---------------------------------------------------------------------------
    # STEP 3: Create ZIP package
    # ---------------------------------------------------------------------------
    # Visual Studio expects templates as ZIP files in the ProjectTemplates folder

    Write-Info "Creating ZIP package..."

    $zipPath = Join-Path $Paths.ProjectTemplates "$($Definition.ZipName).zip"

    # Remove existing ZIP if present
    if (Test-Path $zipPath) {
        Remove-Item $zipPath -Force
    }

    # Create the ZIP archive
    # Using Compress-Archive for simplicity and compatibility
    Compress-Archive -Path (Join-Path $stagingPath "*") -DestinationPath $zipPath -Force

    if (Test-Path $zipPath) {
        $zipSize = [math]::Round((Get-Item $zipPath).Length / 1KB, 2)
        Write-Success "$($Definition.ZipName).zip created (${zipSize} KB)"
        return $true
    } else {
        Write-Failure "Failed to create ZIP package"
        return $false
    }
}

function Generate-VSTemplateXml {
    <#
    .SYNOPSIS
        Generates the MyTemplate.vstemplate XML content.

    .DESCRIPTION
        Creates a properly formatted .vstemplate file that Visual Studio
        uses to understand how to create new projects from this template.

        The vstemplate includes:
        - Template metadata (name, description, icon)
        - Project file reference
        - List of all files to include
        - Parameter replacement settings

    .PARAMETER Definition
        Template definition hashtable.

    .PARAMETER StagingPath
        Path to the staging directory containing template files.

    .OUTPUTS
        XML content as a string.
    #>
    param(
        [hashtable]$Definition,
        [string]$StagingPath
    )

    # Determine project file extension based on language
    $projExtension = if ($Definition.Language -eq "CSharp") { "*.csproj" } else { "*.vbproj" }

    # Find the project file
    $projFile = Get-ChildItem -Path $StagingPath -Filter $projExtension -Recurse | Select-Object -First 1
    if (-not $projFile) {
        throw "No project file ($projExtension) found in $StagingPath"
    }

    # Get all files for the ProjectItem elements
    $allFiles = Get-ChildItem -Path $StagingPath -Recurse -File | Where-Object {
        $_.Name -ne "MyTemplate.vstemplate" -and
        $_.Extension -ne ".csproj" -and
        $_.Extension -ne ".vbproj"
    }

    # Build ProjectItem XML elements
    # Files that need parameter replacement get ReplaceParameters="true"
    $projectItems = ""
    foreach ($file in $allFiles) {
        $relativePath = $file.FullName.Substring($StagingPath.Length + 1)
        $fileName = $file.Name

        # Determine if this file needs parameter replacement
        # Source code files, config files, and text files typically do
        $replaceParams = $false
        $replaceExtensions = @(".cs", ".vb", ".adc", ".xml", ".config", ".json", ".py", ".txt", ".md")
        if ($replaceExtensions -contains $file.Extension.ToLower()) {
            $replaceParams = $true
        }

        $replaceAttr = if ($replaceParams) { ' ReplaceParameters="true"' } else { "" }

        # Handle subdirectories
        $relativeDir = Split-Path $relativePath -Parent
        if ($relativeDir) {
            # File is in a subdirectory - will be handled by folder structure
            continue
        }

        $projectItems += "      <ProjectItem$replaceAttr TargetFileName=`"$fileName`">$fileName</ProjectItem>`r`n"
    }

    # Handle subdirectories (like "scripts" folder)
    $subdirs = Get-ChildItem -Path $StagingPath -Directory | Where-Object { $_.Name -ne ".template.config" }
    $folderElements = ""
    foreach ($subdir in $subdirs) {
        $folderName = $subdir.Name
        $folderItems = ""
        $subFiles = Get-ChildItem -Path $subdir.FullName -File -Recurse
        foreach ($subFile in $subFiles) {
            $subFileName = $subFile.Name
            $replaceParams = $false
            $replaceExtensions = @(".cs", ".vb", ".adc", ".xml", ".config", ".json", ".py", ".txt", ".md")
            if ($replaceExtensions -contains $subFile.Extension.ToLower()) {
                $replaceParams = $true
            }
            $replaceAttr = if ($replaceParams) { ' ReplaceParameters="true"' } else { "" }
            $folderItems += "        <ProjectItem$replaceAttr TargetFileName=`"$subFileName`">$subFileName</ProjectItem>`r`n"
        }
        if ($folderItems) {
            $folderElements += "      <Folder Name=`"$folderName`" TargetFolderName=`"$folderName`">`r`n$folderItems      </Folder>`r`n"
        }
    }

    # Build the complete vstemplate XML
    # This follows the VS 2017+ template schema
    $xml = @"
<?xml version="1.0" encoding="utf-8"?>
<VSTemplate Version="3.0.0" Type="Project" xmlns="http://schemas.microsoft.com/developer/vstemplate/2005" xmlns:sdk="http://schemas.microsoft.com/developer/vstemplate-sdkextension/2010">
  <TemplateData>
    <Name>$($Definition.DisplayName)</Name>
    <Description>$($Definition.Description)</Description>
    <Icon>__TemplateIcon.ico</Icon>
    <ProjectType>$($Definition.Language)</ProjectType>
    <SortOrder>$($Definition.SortOrder)</SortOrder>
    <TemplateGroupID>AlibreDesign</TemplateGroupID>
    <TemplateID>$($Definition.ZipName)</TemplateID>
    <LanguageTag>$($Definition.Language)</LanguageTag>
    <PlatformTag>Windows</PlatformTag>
    <ProjectTypeTag>AlibreDesignExtension</ProjectTypeTag>
    <DefaultName>$($Definition.DefaultName)</DefaultName>
    <ProvideDefaultName>true</ProvideDefaultName>
    <CreateNewFolder>true</CreateNewFolder>
    <LocationField>Enabled</LocationField>
    <EnableLocationBrowseButton>true</EnableLocationBrowseButton>
    <CreateInPlace>true</CreateInPlace>
  </TemplateData>
  <TemplateContent>
    <Project File="$($projFile.Name)" ReplaceParameters="true" TargetFileName="`$safeprojectname`$$($projFile.Extension)">
$projectItems$folderElements    </Project>
  </TemplateContent>
</VSTemplate>
"@

    return $xml
}

function Build-AllTemplates {
    <#
    .SYNOPSIS
        Builds all templates that match the filter.

    .DESCRIPTION
        Iterates through template definitions and builds each one.
        Reports success/failure counts at the end.
    #>

    Write-Header "Building Template Packages"

    $successCount = 0
    $failCount = 0

    # Filter templates if requested
    $templatesToBuild = $TemplateDefinitions | Where-Object {
        $_.ZipName -like $TemplateFilter
    }

    Write-Info "Building $($templatesToBuild.Count) template(s)..."
    Write-Host ""

    foreach ($template in $templatesToBuild) {
        try {
            $result = Build-SingleTemplate -Definition $template
            if ($result) {
                $successCount++
            } else {
                $failCount++
            }
        }
        catch {
            Write-Failure "Error building $($template.DisplayName): $_"
            $failCount++
        }
        Write-Host ""
    }

    # Summary
    Write-Host "  ----------------------------------------" -ForegroundColor Gray
    $summaryColor = if ($failCount -eq 0) { "Green" } else { "Yellow" }
    Write-Host "  Templates: $successCount succeeded, $failCount failed" -ForegroundColor $summaryColor

    return ($failCount -eq 0)
}

function Build-VSIXExtension {
    <#
    .SYNOPSIS
        Builds the VSIX extension package.

    .DESCRIPTION
        Invokes MSBuild to compile the VSIX project, which packages
        all templates into a single .vsix file for distribution.
    #>

    Write-Header "Building VSIX Extension"

    # Find MSBuild
    $msbuild = Find-MSBuild
    if (-not $msbuild) {
        Write-Failure "MSBuild not found. Install Visual Studio 2022 or 2026."
        return $false
    }
    Write-Info "Using MSBuild: $msbuild"
    Write-Info "Configuration: $Configuration"

    # Find the project file
    $vbprojPath = Join-Path $Paths.Extension "VSExtensionForAlibreDesign.vbproj"
    if (-not (Test-Path $vbprojPath)) {
        Write-Failure "VSIX project not found: $vbprojPath"
        return $false
    }

    # Build arguments
    $buildArgs = @(
        $vbprojPath,
        "/t:Rebuild",
        "/p:Configuration=$Configuration",
        "/p:DeployExtension=false",
        "/verbosity:minimal",
        "/restore"
    )

    Write-Step "Building VSIX..."
    Write-Host ""

    # Execute MSBuild
    & $msbuild @buildArgs
    $exitCode = $LASTEXITCODE

    Write-Host ""

    if ($exitCode -eq 0) {
        # Find the output VSIX
        $vsixPath = Join-Path $Paths.Extension "bin\$Configuration\VSExtensionForAlibreDesign.vsix"
        if (Test-Path $vsixPath) {
            $vsixSize = [math]::Round((Get-Item $vsixPath).Length / 1KB, 2)
            Write-Success "VSIX built successfully (${vsixSize} KB)"
            Write-Info "Output: $vsixPath"
            return $true
        }
    }

    Write-Failure "VSIX build failed (exit code: $exitCode)"
    return $false
}

function Build-NuGetPackage {
    <#
    .SYNOPSIS
        Builds the NuGet package for CLI templates.

    .DESCRIPTION
        Creates a .nupkg file that can be installed via 'dotnet new install'.
        This allows users to create Alibre AddOn projects from the command line.
    #>

    Write-Header "Building NuGet Package (CLI Templates)"

    # Check if dotnet templates directory exists
    if (-not (Test-Path $Paths.DotnetTemplates)) {
        Write-Failure "CLI templates directory not found: $($Paths.DotnetTemplates)"
        return $false
    }

    # Find or download nuget.exe
    $nugetExe = Join-Path $Paths.Temp "nuget.exe"
    if (-not (Test-Path $nugetExe)) {
        Write-Step "Downloading nuget.exe..."
        try {
            $nugetUrl = "https://dist.nuget.org/win-x86-commandline/latest/nuget.exe"
            Invoke-WebRequest -Uri $nugetUrl -OutFile $nugetExe
            Write-Success "Downloaded nuget.exe"
        }
        catch {
            Write-Failure "Failed to download nuget.exe: $_"
            return $false
        }
    }

    # Find the nuspec file
    $nuspecPath = Join-Path $Paths.DotnetTemplates "Alibre.Templates.nuspec"
    if (-not (Test-Path $nuspecPath)) {
        Write-Failure "NuSpec file not found: $nuspecPath"
        return $false
    }

    # Create output directory
    $packagesDir = Join-Path $Paths.DotnetTemplates "packages"
    if (-not (Test-Path $packagesDir)) {
        New-Item -ItemType Directory -Path $packagesDir -Force | Out-Null
    }

    Write-Step "Packing NuGet package..."

    # Run nuget pack
    Push-Location $Paths.DotnetTemplates
    try {
        & $nugetExe pack $nuspecPath -OutputDirectory $packagesDir -NoPackageAnalysis
        $exitCode = $LASTEXITCODE
    }
    finally {
        Pop-Location
    }

    if ($exitCode -eq 0) {
        $nupkg = Get-ChildItem -Path $packagesDir -Filter "*.nupkg" | Sort-Object LastWriteTime -Descending | Select-Object -First 1
        if ($nupkg) {
            $pkgSize = [math]::Round($nupkg.Length / 1KB, 2)
            Write-Success "NuGet package created (${pkgSize} KB)"
            Write-Info "Output: $($nupkg.FullName)"
            Write-Host ""
            Write-Info "To install locally:"
            Write-Host "    dotnet new install $($nupkg.FullName)" -ForegroundColor White
            return $true
        }
    }

    Write-Failure "NuGet package build failed"
    return $false
}

function Cleanup-BuildEnvironment {
    <#
    .SYNOPSIS
        Cleans up temporary files after build.

    .DESCRIPTION
        Removes the temp directory and any other build artifacts
        that aren't needed after the build completes.
    #>

    Write-Info "Cleaning up temporary files..."

    if (Test-Path $Paths.Temp) {
        Remove-Item $Paths.Temp -Recurse -Force -ErrorAction SilentlyContinue
    }
}

# ==============================================================================
# MAIN EXECUTION
# ==============================================================================
# This is the entry point when the script runs

Write-Host ""
Write-Host "============================================================" -ForegroundColor Cyan
Write-Host "  Alibre Design Extension - Template Build System" -ForegroundColor Cyan
Write-Host "  Version 1.0.0 | $(Get-Date -Format 'yyyy-MM-dd HH:mm')" -ForegroundColor Cyan
Write-Host "============================================================" -ForegroundColor Cyan

$startTime = Get-Date
$overallSuccess = $true

try {
    # Phase 1: Initialize
    Initialize-BuildEnvironment

    # Phase 2: Build template packages
    $templatesOk = Build-AllTemplates
    if (-not $templatesOk) {
        $overallSuccess = $false
    }

    # Phase 3: Build VSIX (if requested)
    if ($BuildVSIX) {
        $vsixOk = Build-VSIXExtension
        if (-not $vsixOk) {
            $overallSuccess = $false
        }
    }

    # Phase 4: Build NuGet (if requested)
    if ($BuildNuGet) {
        $nugetOk = Build-NuGetPackage
        if (-not $nugetOk) {
            $overallSuccess = $false
        }
    }
}
catch {
    Write-Failure "Build failed with error: $_"
    $overallSuccess = $false
}
finally {
    # Always cleanup temp files
    Cleanup-BuildEnvironment
}

# ==============================================================================
# BUILD SUMMARY
# ==============================================================================

$endTime = Get-Date
$duration = $endTime - $startTime

Write-Host ""
Write-Host "============================================================" -ForegroundColor Cyan
Write-Host "  BUILD SUMMARY" -ForegroundColor Cyan
Write-Host "============================================================" -ForegroundColor Cyan
Write-Host ""
Write-Host "  Duration: $([math]::Round($duration.TotalSeconds, 1)) seconds" -ForegroundColor Gray
Write-Host ""

if ($overallSuccess) {
    Write-Host "  [SUCCESS] Build completed successfully!" -ForegroundColor Green
} else {
    Write-Host "  [WARNING] Build completed with errors" -ForegroundColor Yellow
}

Write-Host ""
Write-Host "  Next steps:" -ForegroundColor Gray
if (-not $BuildVSIX) {
    Write-Host "    - Run with -BuildVSIX to create VSIX package" -ForegroundColor Gray
}
if (-not $BuildNuGet) {
    Write-Host "    - Run with -BuildNuGet to create NuGet package" -ForegroundColor Gray
}
Write-Host "    - Test templates in Visual Studio" -ForegroundColor Gray
Write-Host ""
