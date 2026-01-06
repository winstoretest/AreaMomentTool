<#
.SYNOPSIS
    Complete headless build script for Alibre Design Visual Studio templates.

.DESCRIPTION
    This script fully automates what Visual Studio's "Export Template Wizard" does
    for BOTH Project Templates and Item Templates. It discovers source code, generates
    all required configuration files, and builds distribution packages.

    TEMPLATE TYPES SUPPORTED:
    -------------------------
    1. PROJECT TEMPLATES (Working/Projects/)
       - Creates new projects from template
       - Appears in File > New > Project dialog
       - Source: Working/Projects/[TemplateName]/

    2. ITEM TEMPLATES (Working/Items/)
       - Adds items to existing projects
       - Appears in Add > New Item dialog
       - Source: Working/Items/[TemplateName]/

    AUTO-DISCOVERY:
    ---------------
    The script scans source folders and automatically:
    - Detects template type (Project vs Item)
    - Detects language (C# or VB.NET)
    - Extracts project GUIDs (for project templates)
    - Generates display names and descriptions
    - Creates .vstemplate files
    - Updates all configuration files

    FILES UPDATED AUTOMATICALLY:
    ----------------------------
    - Extension/VSExtensionForAlibreVB/VSExtensionForAlibreVB.vbproj
      (Content items for ZIPs, ProjectReference items)
    - Extension/VSExtensionForAlibreVB/source.extension.vsixmanifest
      (Asset entries for project and item templates)
    - AlibreExtensions.slnx
      (Working folder project references)
    - Templates/dotnet/Alibre.Templates.nuspec
      (CLI template file references)

    OUTPUT PRODUCED:
    ----------------
    - Project template ZIPs: Extension/.../ProjectTemplates/*.zip
    - Item template ZIPs:    Extension/.../ItemTemplates/*.zip
    - VSIX extension:        Extension/.../bin/Release/*.vsix
    - NuGet package:         bin/*.nupkg

    MICROSOFT DOCUMENTATION REFERENCES:
    -----------------------------------
    - VSIX Extension Schema 2.0: https://learn.microsoft.com/en-us/visualstudio/extensibility/vsix-extension-schema-2-0-reference
    - Visual Studio Template Schema: https://learn.microsoft.com/en-us/visualstudio/extensibility/visual-studio-template-schema-reference
    - TemplateData Element: https://learn.microsoft.com/en-us/visualstudio/extensibility/templatedata-element-visual-studio-templates
    - ProjectItem Element: https://learn.microsoft.com/en-us/visualstudio/extensibility/projectitem-element-visual-studio-project-templates
    - Template Parameters: https://learn.microsoft.com/en-us/visualstudio/ide/template-parameters
    - Best Practices Checklist: https://learn.microsoft.com/en-us/visualstudio/extensibility/vsix/publish/checklist

.PARAMETER Configuration
    Build configuration: Debug or Release. Default is Release.

.PARAMETER SkipVSIX
    Skip building the VSIX package.

.PARAMETER SkipNuGet
    Skip building the NuGet package.

.PARAMETER Clean
    Remove all existing build outputs before building.

.PARAMETER UpdateOnly
    Only update configuration files, don't build.

.PARAMETER WhatIf
    Show what would be changed without making changes.

.EXAMPLE
    .\Build-All.ps1

    Discovers all templates, updates configs, builds everything.

.EXAMPLE
    .\Build-All.ps1 -UpdateOnly

    Only updates configuration files without building.

.EXAMPLE
    .\Build-All.ps1 -Clean

    Clean build with all outputs regenerated.

.NOTES
    Author: Stephen S. Mitchell
    Version: 4.0.0
    Date: December 2025

    ADDING A NEW PROJECT TEMPLATE:
    ------------------------------
    1. Create your project in Working/Projects/YourTemplateName/
    2. Run .\Build-All.ps1
    3. The script automatically integrates it

    ADDING A NEW ITEM TEMPLATE:
    ---------------------------
    1. Create folder Working/Items/YourItemName/
    2. Add source file(s) with template parameters:
       - $safeitemname$ - Safe item name
       - $rootnamespace$ - Project namespace
       - $time$, $year$, $username$ - Metadata
    3. Optionally add an icon (.ico or .png)
    4. Run .\Build-All.ps1

.LINK
    https://github.com/Testbed-for-Alibre-Design/AlibreExtensions
#>

# ==============================================================================
# SCRIPT PARAMETERS
# ==============================================================================

[CmdletBinding(SupportsShouldProcess)]
param(
    [ValidateSet("Debug", "Release")]
    [string]$Configuration = "Release",

    [switch]$SkipVSIX,
    [switch]$SkipNuGet,
    [switch]$Clean,
    [switch]$UpdateOnly
)

# ==============================================================================
# CONFIGURATION
# ==============================================================================

$ErrorActionPreference = "Stop"
$script:StartTime = Get-Date

# Root directory is where this script lives
$script:RootDir = $PSScriptRoot
if (-not $script:RootDir) {
    $script:RootDir = Split-Path -Parent $MyInvocation.MyCommand.Path
}
if (-not $script:RootDir) {
    $script:RootDir = Get-Location
}

# ==============================================================================
# LOAD CONFIGURATION FROM build.config.json
# ==============================================================================

$script:ConfigPath = Join-Path $script:RootDir "build.config.json"
if (-not (Test-Path $script:ConfigPath)) {
    throw "Configuration file not found: $script:ConfigPath"
}

try {
    $script:Config = Get-Content $script:ConfigPath -Raw | ConvertFrom-Json
} catch {
    throw "Failed to parse configuration file: $_"
}

# Helper function to get config value with fallback
function Get-ConfigValue {
    param([string]$Path, $Default = $null)
    $parts = $Path -split '\.'
    $value = $script:Config
    foreach ($part in $parts) {
        if ($null -eq $value) { return $Default }
        $value = $value.$part
    }
    if ($null -eq $value) { return $Default }
    return $value
}

# Build version string from config
$script:VersionMajor = Get-ConfigValue "version.major" 1
$script:VersionMinor = Get-ConfigValue "version.minor" 0
$script:VersionPatch = Get-ConfigValue "version.patch" 0
$script:VersionLabel = Get-ConfigValue "version.label" ""
$script:Version = "$script:VersionMajor.$script:VersionMinor.$script:VersionPatch"
if ($script:VersionLabel) { $script:Version += "-$script:VersionLabel" }

# Product information from config
$script:ProductName = Get-ConfigValue "product.name" "Alibre Design"
$script:ProductShortName = Get-ConfigValue "product.shortName" "AlibreDesign"
$script:ProductDisplayName = Get-ConfigValue "product.displayName" "Alibre Design Extension for Visual Studio"
$script:Publisher = Get-ConfigValue "product.publisher" "unknown"
$script:Author = Get-ConfigValue "product.author" "Unknown Author"

# Extension information from config
$script:ExtensionFolder = Get-ConfigValue "extension.folderName" "VSExtensionForAlibreDesign"
$script:ExtensionProjectFile = Get-ConfigValue "extension.projectFile" "VSExtensionForAlibreDesign.vbproj"
$script:ExtensionOutputName = Get-ConfigValue "extension.outputName" "VSExtensionForAlibreDesign"

# NuGet information from config
$script:NuGetPackageId = Get-ConfigValue "nuget.packageId" "AlibreDesign.Templates"
$script:NuSpecFileName = Get-ConfigValue "nuget.nuspecFile" "AlibreDesign.Templates.nuspec"

# Start transcript logging
$logDir = Join-Path $script:RootDir (Get-ConfigValue "paths.logs" "Docs/_logs")
if (-not (Test-Path $logDir)) {
    New-Item -ItemType Directory -Path $logDir -Force | Out-Null
}
$timestamp = Get-Date -Format "yyyy-MM-dd_HH-mm-ss"
$script:LogPath = Join-Path $logDir "log-cli-build-$timestamp.txt"
Start-Transcript -Path $script:LogPath -Force | Out-Null

# All paths relative to root - built dynamically from config
$extensionPath = Join-Path $script:RootDir (Get-ConfigValue "paths.extension" "Extension")
$extensionFullPath = Join-Path $extensionPath $script:ExtensionFolder
$templatesPath = Join-Path $script:RootDir (Get-ConfigValue "paths.templates" "Templates/dotnet")

$script:Paths = @{
    Root              = $script:RootDir
    # Source folders
    Working           = Join-Path $script:RootDir (Get-ConfigValue "paths.working" "Working/Projects")
    WorkingItems      = Join-Path $script:RootDir (Get-ConfigValue "paths.workingItems" "Working/Items")
    # Extension paths (dynamically constructed)
    Extension         = $extensionFullPath
    ExtensionProject  = Join-Path $extensionFullPath $script:ExtensionProjectFile
    VSIXManifest      = Join-Path $extensionFullPath "source.extension.vsixmanifest"
    ProjectTemplates  = Join-Path $extensionFullPath "ProjectTemplates"
    ItemTemplates     = Join-Path $extensionFullPath "ItemTemplates"
    # Solution and CLI
    SolutionFile      = Join-Path $script:RootDir (Get-ConfigValue "solution.fileName" "AlibreExtensions-All.slnx")
    DotnetTemplates   = $templatesPath
    NuSpec            = Join-Path $templatesPath $script:NuSpecFileName
    NuGetOutput       = Join-Path $script:RootDir (Get-ConfigValue "paths.bin" "bin")
    # Build directories
    BinOutput         = Join-Path $script:RootDir (Get-ConfigValue "paths.bin" "bin")
    Staging           = Join-Path $script:RootDir (Get-ConfigValue "paths.staging" "_staging")
    Temp              = Join-Path $script:RootDir (Get-ConfigValue "paths.temp" "_temp")
    # Documentation
    Audit             = Join-Path $script:RootDir (Get-ConfigValue "paths.audit" "Docs/_audit")
    Docs              = Join-Path $script:RootDir (Get-ConfigValue "paths.docs" "Docs")
}

# Template Group ID for organizing templates in VS dialogs (from config)
# Reference: https://learn.microsoft.com/en-us/visualstudio/extensibility/templategroupid-element-visual-studio-templates
$script:TemplateGroupID = Get-ConfigValue "templates.groupId" "AlibreDesign"

# File extensions for template parameter replacement (from config)
$script:ReplaceParameterExtensions = Get-ConfigValue "build.replaceParameterExtensions" @(
    ".cs", ".vb", ".fs", ".csproj", ".vbproj", ".fsproj", ".adc",
    ".xml", ".config", ".json", ".py", ".txt", ".md",
    ".xaml", ".resx", ".settings"
)

# Patterns to exclude from template packages (from config)
$script:ExcludePatterns = Get-ConfigValue "build.excludePatterns" @(
    "bin", "obj", ".vs", ".git", ".gitignore", ".gitattributes",
    "*.user", "*.suo", "*.log", "packages", "node_modules",
    ".template.config", "TestResults", "*.DotSettings.user", ".claude"
)

# ==============================================================================
# CONSOLE OUTPUT FUNCTIONS
# ==============================================================================

function Write-Banner {
    $banner = @"

================================================================================
     _    _ _ _               _____      _                 _
    / \  | (_) |__  _ __ ___ | ____|_  _| |_ ___ _ __  ___(_) ___  _ __  ___
   / _ \ | | | '_ \| '__/ _ \|  _| \ \/ / __/ _ \ '_ \/ __| |/ _ \| '_ \/ __|
  / ___ \| | | |_) | | |  __/| |___ >  <| ||  __/ | | \__ \ | (_) | | | \__ \
 /_/   \_\_|_|_.__/|_|  \___||_____/_/\_\\__\___|_| |_|___/_|\___/|_| |_|___/

              $($script:ProductName) BUILD SYSTEM v$($script:Version)
              Project Templates + Item Templates
================================================================================
  Project Root: $($script:RootDir)
  Configuration: $Configuration
  Product: $($script:ProductDisplayName)
  Publisher: $($script:Publisher)
  Date: $(Get-Date -Format "yyyy-MM-dd HH:mm:ss")
================================================================================

"@
    Write-Host $banner -ForegroundColor Cyan
}

function Write-Section {
    param([string]$Title)
    Write-Host ""
    Write-Host ("=" * 78) -ForegroundColor DarkCyan
    Write-Host "  $Title" -ForegroundColor White
    Write-Host ("=" * 78) -ForegroundColor DarkCyan
    Write-Host ""
}

function Write-Step {
    param([string]$Text)
    Write-Host "  [*] $Text" -ForegroundColor Cyan
}

function Write-SubStep {
    param([string]$Text)
    Write-Host "      - $Text" -ForegroundColor Gray
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
    Write-Host "  [i] $Text" -ForegroundColor DarkGray
}

function Write-Change {
    param([string]$Text)
    Write-Host "  [+] $Text" -ForegroundColor Yellow
}

# ==============================================================================
# TEMPLATE DISCOVERY - PROJECT TEMPLATES
# ==============================================================================

function Get-DiscoveredProjectTemplates {
    <#
    .SYNOPSIS
        Discovers all project templates in the Working directory.

    .DESCRIPTION
        Scans Working/ for .csproj and .vbproj files and extracts metadata
        to generate template definitions.
    #>

    Write-Step "Discovering PROJECT templates in Working/Projects/..."

    $templates = @()

    if (-not (Test-Path $script:Paths.Working)) {
        Write-SubStep "Working/Projects/ directory not found - no project templates"
        return $templates
    }

    $projectFiles = Get-ChildItem -Path $script:Paths.Working -Recurse -Include "*.csproj", "*.vbproj", "*.fsproj" -File |
                    Where-Object { $_.FullName -notmatch "\\(bin|obj)\\" }

    foreach ($projectFile in $projectFiles) {
        try {
            $relativePath = $projectFile.FullName.Substring($script:Paths.Working.Length + 1)
            $folderName = $relativePath.Split('\')[0]

            # Skip if already processed
            if ($templates | Where-Object { $_.FolderName -eq $folderName }) { continue }

            # Determine language
            $language = switch ($projectFile.Extension) {
                ".csproj" { "CSharp" }
                ".fsproj" { "FSharp" }
                ".vbproj" { "VisualBasic" }
                default { "CSharp" }
            }
            $langShort = switch ($language) {
                "CSharp" { "CS" }
                "FSharp" { "FS" }
                "VisualBasic" { "VB" }
                default { "CS" }
            }
            $langDisplay = switch ($language) {
                "CSharp" { "C#" }
                "FSharp" { "F#" }
                "VisualBasic" { "VB.NET" }
                default { "C#" }
            }

            # Extract project GUID and check for template parameters
            $projectGuid = $null
            $canCompile = $true
            try {
                $projContent = Get-Content $projectFile.FullName -Raw
                [xml]$projXml = [xml]$projContent
                $guidNode = $projXml.SelectSingleNode("//*[local-name()='ProjectGuid']")
                if ($guidNode) { $projectGuid = $guidNode.InnerText.Trim() }

                # Check if project file contains template parameters that prevent compilation
                # Template parameters like $safeprojectname$ in RootNamespace make the project non-compilable
                if ($projContent -match '\$safeprojectname\$|\$projectname\$') {
                    $canCompile = $false
                }

                # Check if this is a .NET Core/.NET 5+ project (SDK-style targeting modern .NET)
                # These cannot be referenced by the .NET Framework 4.8.1 VSIX project
                # Use regex directly on project content for more reliable detection
                $isSdkStyle = $projContent -match '<Project\s+Sdk='
                if ($isSdkStyle) {
                    # Extract TargetFramework value using regex (more reliable than XML parsing for SDK projects)
                    if ($projContent -match '<TargetFramework[s]?>([^<]+)</TargetFramework') {
                        $tfm = $matches[1]
                        # Exclude net5.0+, netcoreapp, netstandard projects from VSIX references
                        # Match net5.0, net6.0, net7.0, net8.0, net9.0+ (with dot separator)
                        # But NOT net481 (which is .NET Framework 4.8.1)
                        if ($tfm -match 'net[5-9]\.|net[1-9]\d+\.|netcoreapp|netstandard') {
                            $canCompile = $false
                        }
                    }
                }
            } catch { }
            if (-not $projectGuid) {
                $projectGuid = "{$([guid]::NewGuid().ToString().ToUpper())}"
            }

            # Generate display name from folder name
            # Convert folder name to a readable display name
            # Handle both "alibre-python-shell-addon" and "AlibreScriptAddonCS" formats
            $displayName = $folderName
            
            # If the name contains hyphens or underscores, replace with spaces and title case
            if ($displayName -match '[-_]') {
                $displayName = $displayName -replace '[-_]', ' '
                $displayName = (Get-Culture).TextInfo.ToTitleCase($displayName.ToLower())
            }
            # If it's PascalCase (like AlibreScriptAddonCS), insert spaces before capitals
            # But avoid splitting common abbreviations like CS, VB, FS
            elseif ($displayName -cmatch '[a-z][A-Z]') {
                # Replace CS, VB, FS, etc. with temporary markers to prevent splitting
                $displayName = $displayName -replace 'CS$', 'ξCSξ'
                $displayName = $displayName -replace 'VB$', 'ξVBξ'
                $displayName = $displayName -replace 'FS$', 'ξFSξ'
                # Insert spaces before capitals (except after another capital)
                $displayName = $displayName -creplace '([a-z])([A-Z])', '$1 $2'
                # Restore abbreviations
                $displayName = $displayName -replace 'ξCSξ', 'CS'
                $displayName = $displayName -replace 'ξVBξ', 'VB'
                $displayName = $displayName -replace 'ξFSξ', 'FS'
                $displayName = $displayName.Trim()
            }
            
            $displayName = "$displayName ($langDisplay)"

            # Generate description from folder name
            $description = "$langDisplay Alibre Design AddOn: $folderName"

            # Sort order - based on language and folder name
            $sortBase = switch ($language) {
                "CSharp" { 100 }
                "FSharp" { 150 }
                "VisualBasic" { 200 }
                default { 100 }
            }
            # Sort offset based on folder name patterns
            $sortOffset = if ($folderName -match "Script") { 0 } 
                         elseif ($folderName -match "Ribbon") { 20 } 
                         else { 10 }

            $template = @{
                Type             = "Project"
                FolderName       = $folderName
                ProjectFile      = $projectFile.FullName
                ProjectRelPath   = $relativePath
                ZipName          = $folderName
                DisplayName      = $displayName
                Description      = $description
                Language         = $language
                LanguageShort    = $langShort
                DefaultName      = if ($folderName -match "Script") { "AlibreScriptAddon" } elseif ($folderName -match "Ribbon") { "AlibreRibbonAddon" } else { "AlibreAddon" }
                SortOrder        = $sortBase + $sortOffset
                TemplateID       = "Alibre.$($folderName -replace 'Alibre', '')"
                ProjectGuid      = $projectGuid
                CliShortName     = if ($folderName -match "Script") { "alibre-script-$($langShort.ToLower())" } elseif ($folderName -match "Ribbon") { "alibre-ribbon-$($langShort.ToLower())" } else { "alibre-addon-$($langShort.ToLower())" }
                CliIdentity      = "Alibre.$folderName"
                CanCompile       = $canCompile  # False if project contains template parameters that prevent compilation
            }

            $templates += $template
            $compileNote = ""
            if (-not $canCompile) {
                if ($projContent -match '\$safeprojectname\$|\$projectname\$') {
                    $compileNote = " [Template-Only]"
                } elseif ($tfm -and $tfm -match 'net[5-9]\.|net[1-9]\d+\.') {
                    $compileNote = " [.NET $tfm]"
                } else {
                    $compileNote = " [No VSIX Ref]"
                }
            }
            Write-SubStep "Found: $folderName ($langDisplay) [Project]$compileNote"

        } catch {
            Write-SubStep "Error processing $($projectFile.Name): $_"
        }
    }

    $templates = $templates | Sort-Object { $_.SortOrder }
    Write-Success "Discovered $($templates.Count) project template(s)"
    return $templates
}

# ==============================================================================
# TEMPLATE DISCOVERY - ITEM TEMPLATES
# ==============================================================================

function Get-DiscoveredItemTemplates {
    <#
    .SYNOPSIS
        Discovers all item templates in the Working/Items directory.

    .DESCRIPTION
        Scans Working/Items/ for source files (.cs, .vb, .xaml, etc.) and
        generates item template definitions.

    .NOTES
        Item template folder structure:
        Working/Items/
        └── AlibreCommand/
            ├── AlibreCommand.vb     (source file with template parameters)
            └── AlibreCommand.ico    (optional icon)
    #>

    Write-Step "Discovering ITEM templates in Working/Items/..."

    $templates = @()

    if (-not (Test-Path $script:Paths.WorkingItems)) {
        Write-SubStep "Working/Items/ directory not found - no item templates"
        return $templates
    }

    # Each subfolder in Working/Items is an item template
    $templateFolders = Get-ChildItem -Path $script:Paths.WorkingItems -Directory

    foreach ($folder in $templateFolders) {
        try {
            $folderName = $folder.Name

            # Find source files (code files)
            $sourceFiles = Get-ChildItem -Path $folder.FullName -File |
                           Where-Object { $_.Extension -in @(".cs", ".vb", ".fs", ".xaml", ".xml", ".json", ".txt") }

            if ($sourceFiles.Count -eq 0) {
                Write-SubStep "Skipping $folderName - no source files found"
                continue
            }

            # Determine language from primary source file
            $primaryFile = $sourceFiles | Select-Object -First 1
            $language = switch ($primaryFile.Extension) {
                ".cs" { "CSharp" }
                ".fs" { "FSharp" }
                ".vb" { "VisualBasic" }
                ".xaml" { "CSharp" }  # XAML typically with C#
                default { "CSharp" }
            }
            $langShort = switch ($language) {
                "CSharp" { "CS" }
                "FSharp" { "FS" }
                "VisualBasic" { "VB" }
                default { "CS" }
            }
            $langDisplay = switch ($language) {
                "CSharp" { "C#" }
                "FSharp" { "F#" }
                "VisualBasic" { "VB.NET" }
                default { "C#" }
            }

            # Look for icon
            $iconFile = Get-ChildItem -Path $folder.FullName -File |
                        Where-Object { $_.Extension -in @(".ico", ".png") } |
                        Select-Object -First 1
            $iconName = if ($iconFile) { $iconFile.Name } else { "__TemplateIcon.ico" }

            # Generate display name from folder name
            # Convert "AlibreCommand" to "Alibre Command"
            $displayName = ($folderName -creplace '([A-Z])', ' $1').Trim()
            $displayName = "$displayName ($langDisplay)"

            # Generate description
            $description = "Adds a new $folderName to your project."

            # Determine default file name
            $defaultName = $primaryFile.Name

            $template = @{
                Type             = "Item"
                FolderName       = $folderName
                FolderPath       = $folder.FullName
                ZipName          = $folderName
                DisplayName      = $displayName
                Description      = $description
                Language         = $language
                LanguageShort    = $langShort
                DefaultName      = $defaultName
                SortOrder        = 10
                TemplateID       = "AlibreDesign.$folderName.$langShort.1.0"
                IconName         = $iconName
                SourceFiles      = $sourceFiles
                IconFile         = $iconFile
            }

            $templates += $template
            Write-SubStep "Found: $folderName ($langDisplay) [Item]"

        } catch {
            Write-SubStep "Error processing $($folder.Name): $_"
        }
    }

    Write-Success "Discovered $($templates.Count) item template(s)"
    return $templates
}

# ==============================================================================
# PROJECT FILE UPDATE FUNCTIONS
# ==============================================================================

function Update-VSIXProject {
    <#
    .SYNOPSIS
        Updates the VSIX .vbproj file with all template references.
    #>
    param(
        [array]$ProjectTemplates,
        [array]$ItemTemplates
    )

    Write-Step "Updating VSIX project file..."

    if (-not (Test-Path $script:Paths.ExtensionProject)) {
        Write-Failure "VSIX project not found: $($script:Paths.ExtensionProject)"
        return $false
    }

    [xml]$proj = Get-Content $script:Paths.ExtensionProject -Encoding UTF8
    $ns = $proj.DocumentElement.NamespaceURI
    $nsManager = New-Object System.Xml.XmlNamespaceManager($proj.NameTable)
    $nsManager.AddNamespace("ms", $ns)

    $modified = $false

    # Find or create ItemGroups
    $contentItemGroup = $null
    $refItemGroup = $null

    foreach ($ig in $proj.Project.ItemGroup) {
        $contentItems = $ig.SelectNodes("ms:Content[contains(@Include, 'Templates')]", $nsManager)
        if ($contentItems.Count -gt 0 -and -not $contentItemGroup) {
            $contentItemGroup = $ig
        }
        $refs = $ig.SelectNodes("ms:ProjectReference[contains(@Include, 'Working')]", $nsManager)
        if ($refs.Count -gt 0) {
            $refItemGroup = $ig
        }
    }

    if (-not $contentItemGroup) {
        $contentItemGroup = $proj.CreateElement("ItemGroup", $ns)
        $proj.Project.AppendChild($contentItemGroup) | Out-Null
    }
    if (-not $refItemGroup) {
        $refItemGroup = $proj.CreateElement("ItemGroup", $ns)
        $proj.Project.AppendChild($refItemGroup) | Out-Null
    }

    # Track existing items
    $existingContent = @{}
    foreach ($content in $contentItemGroup.SelectNodes("ms:Content", $nsManager)) {
        $include = $content.GetAttribute("Include")
        $existingContent[$include] = $content
    }

    $existingRefs = @{}
    foreach ($ref in $refItemGroup.SelectNodes("ms:ProjectReference", $nsManager)) {
        $include = $ref.GetAttribute("Include")
        # Path format: ..\..\Working\Projects\<FolderName>\<Project>.csproj
        if ($include -match "Working\\Projects\\([^\\]+)") {
            $existingRefs[$matches[1]] = $ref
        }
    }

    # --- PROJECT TEMPLATES ---
    foreach ($template in $ProjectTemplates) {
        $zipInclude = "ProjectTemplates\$($template.ZipName).zip"

        if (-not $existingContent.ContainsKey($zipInclude)) {
            Write-Change "Adding ProjectTemplate ZIP: $($template.ZipName).zip"

            $contentItem = $proj.CreateElement("Content", $ns)
            $contentItem.SetAttribute("Include", $zipInclude)

            $copyOutput = $proj.CreateElement("CopyToOutputDirectory", $ns)
            $copyOutput.InnerText = "Always"
            $contentItem.AppendChild($copyOutput) | Out-Null

            $includeVsix = $proj.CreateElement("IncludeInVSIX", $ns)
            $includeVsix.InnerText = "true"
            $contentItem.AppendChild($includeVsix) | Out-Null

            $contentItemGroup.AppendChild($contentItem) | Out-Null
            $modified = $true
        }

        # ProjectReference - only add for templates that can be compiled
        # Templates with $safeprojectname$ in the project file cannot be compiled by MSBuild
        if (-not $existingRefs.ContainsKey($template.FolderName) -and $template.CanCompile) {
            Write-Change "Adding project reference: $($template.FolderName)"

            $projRef = $proj.CreateElement("ProjectReference", $ns)
            $relPath = "..\..\Working\Projects\$($template.ProjectRelPath)"
            $projRef.SetAttribute("Include", $relPath)

            $guidElem = $proj.CreateElement("Project", $ns)
            $guidElem.InnerText = $template.ProjectGuid
            $projRef.AppendChild($guidElem) | Out-Null

            $nameElem = $proj.CreateElement("Name", $ns)
            $nameElem.InnerText = $template.FolderName
            $projRef.AppendChild($nameElem) | Out-Null

            $subPath = $proj.CreateElement("VSIXSubPath", $ns)
            $subPath.InnerText = "ProjectTemplates"
            $projRef.AppendChild($subPath) | Out-Null

            $refOutput = $proj.CreateElement("ReferenceOutputAssembly", $ns)
            $refOutput.InnerText = "false"
            $projRef.AppendChild($refOutput) | Out-Null

            $includeGroups = $proj.CreateElement("IncludeOutputGroupsInVSIX", $ns)
            $projRef.AppendChild($includeGroups) | Out-Null

            $refItemGroup.AppendChild($projRef) | Out-Null
            $modified = $true
        }
    }

    # --- ITEM TEMPLATES ---
    foreach ($template in $ItemTemplates) {
        $zipInclude = "ItemTemplates\$($template.ZipName).zip"

        if (-not $existingContent.ContainsKey($zipInclude)) {
            Write-Change "Adding ItemTemplate ZIP: $($template.ZipName).zip"

            $contentItem = $proj.CreateElement("Content", $ns)
            $contentItem.SetAttribute("Include", $zipInclude)

            $copyOutput = $proj.CreateElement("CopyToOutputDirectory", $ns)
            $copyOutput.InnerText = "Always"
            $contentItem.AppendChild($copyOutput) | Out-Null

            $includeVsix = $proj.CreateElement("IncludeInVSIX", $ns)
            $includeVsix.InnerText = "true"
            $contentItem.AppendChild($includeVsix) | Out-Null

            $contentItemGroup.AppendChild($contentItem) | Out-Null
            $modified = $true
        }
    }

    if ($modified) {
        if ($PSCmdlet.ShouldProcess($script:Paths.ExtensionProject, "Update VSIX project")) {
            $proj.Save($script:Paths.ExtensionProject)
            Write-Success "VSIX project updated"
        }
    } else {
        Write-Info "VSIX project already up to date"
    }

    return $true
}

function Update-SolutionFile {
    param([array]$ProjectTemplates)

    Write-Step "Updating solution file..."

    if (-not (Test-Path $script:Paths.SolutionFile)) {
        Write-Failure "Solution file not found"
        return $false
    }

    [xml]$sln = Get-Content $script:Paths.SolutionFile -Encoding UTF8
    $modified = $false

    $workingFolder = $sln.Solution.Folder | Where-Object { $_.Name -eq "/Working/" }
    if (-not $workingFolder) {
        $workingFolder = $sln.CreateElement("Folder")
        $workingFolder.SetAttribute("Name", "/Working/")
        $sln.Solution.AppendChild($workingFolder) | Out-Null
        $modified = $true
    }

    $existingProjects = @{}
    foreach ($proj in $workingFolder.Project) {
        $path = $proj.GetAttribute("Path")
        $existingProjects[$path] = $proj
    }

    foreach ($template in $ProjectTemplates) {
        # Skip templates that can't be compiled (contain template parameters like $safeprojectname$)
        if (-not $template.CanCompile) {
            continue
        }

        $projPath = "Working/Projects/$($template.ProjectRelPath -replace '\\', '/')"
        if (-not $existingProjects.ContainsKey($projPath)) {
            Write-Change "Adding to solution: $projPath"
            $projElem = $sln.CreateElement("Project")
            $projElem.SetAttribute("Path", $projPath)
            $workingFolder.AppendChild($projElem) | Out-Null
            $modified = $true
        }
    }

    if ($modified) {
        if ($PSCmdlet.ShouldProcess($script:Paths.SolutionFile, "Update solution")) {
            $sln.Save($script:Paths.SolutionFile)
            Write-Success "Solution file updated"
        }
    } else {
        Write-Info "Solution file already up to date"
    }

    return $true
}

function Update-NuSpec {
    param([array]$ProjectTemplates)

    Write-Step "Updating NuSpec file..."

    if (-not (Test-Path $script:Paths.NuSpec)) {
        Write-Info "NuSpec not found, skipping"
        return $true
    }

    [xml]$nuspec = Get-Content $script:Paths.NuSpec -Encoding UTF8
    $modified = $false

    $filesElem = $nuspec.package.files
    if (-not $filesElem) {
        $filesElem = $nuspec.CreateElement("files")
        $nuspec.package.AppendChild($filesElem) | Out-Null
    }

    $existingFiles = @{}
    foreach ($file in $filesElem.file) {
        $src = $file.GetAttribute("src")
        $existingFiles[$src] = $file
    }

    foreach ($template in $ProjectTemplates) {
        $cliPath = Join-Path $script:Paths.DotnetTemplates $template.FolderName
        if (-not (Test-Path $cliPath)) { continue }

        $srcPattern = "$($template.FolderName)\**\*"
        if (-not $existingFiles.ContainsKey($srcPattern)) {
            Write-Change "Adding NuSpec: $($template.FolderName)"
            $fileElem = $nuspec.CreateElement("file")
            $fileElem.SetAttribute("src", $srcPattern)
            $fileElem.SetAttribute("target", "content\$($template.FolderName)")
            $filesElem.AppendChild($fileElem) | Out-Null
            $modified = $true
        }
    }

    if ($modified) {
        if ($PSCmdlet.ShouldProcess($script:Paths.NuSpec, "Update NuSpec")) {
            $nuspec.Save($script:Paths.NuSpec)
            Write-Success "NuSpec updated"
        }
    } else {
        Write-Info "NuSpec already up to date"
    }

    return $true
}

function Update-VSIXManifest {
    <#
    .SYNOPSIS
        Updates the VSIX manifest with item template asset entries.

    .DESCRIPTION
        Dynamically adds Asset elements for item templates to source.extension.vsixmanifest.

        Documentation References:
        - VSIX Extension Schema 2.0: https://learn.microsoft.com/en-us/visualstudio/extensibility/vsix-extension-schema-2-0-reference
        - Asset Element: https://learn.microsoft.com/en-us/visualstudio/extensibility/vsix-extension-schema-2-0-reference#asset-element

        Asset Types:
        - Microsoft.VisualStudio.ProjectTemplate: Project templates (File > New > Project)
        - Microsoft.VisualStudio.ItemTemplate: Item templates (Add > New Item)
    #>
    param(
        [array]$ProjectTemplates,
        [array]$ItemTemplates
    )

    Write-Step "Updating VSIX manifest..."

    if (-not (Test-Path $script:Paths.VSIXManifest)) {
        Write-Failure "VSIX manifest not found: $($script:Paths.VSIXManifest)"
        return $false
    }

    [xml]$manifest = Get-Content $script:Paths.VSIXManifest -Encoding UTF8
    $ns = $manifest.DocumentElement.NamespaceURI
    $nsD = "http://schemas.microsoft.com/developer/vsx-schema-design/2011"
    $nsManager = New-Object System.Xml.XmlNamespaceManager($manifest.NameTable)
    $nsManager.AddNamespace("vs", $ns)
    $nsManager.AddNamespace("d", $nsD)

    $assetsNode = $manifest.PackageManifest.Assets
    if (-not $assetsNode) {
        Write-Failure "Assets node not found in VSIX manifest"
        return $false
    }

    $modified = $false

    # Build set of existing asset target paths
    $existingAssets = @{}
    foreach ($asset in $assetsNode.Asset) {
        $targetPath = $asset.GetAttribute("TargetPath", $nsD)
        if ($targetPath) {
            $existingAssets[$targetPath] = $asset
        }
    }

    # --- PROJECT TEMPLATES ---
    foreach ($template in $ProjectTemplates) {
        $targetPath = "ProjectTemplates\$($template.ZipName).zip"

        if (-not $existingAssets.ContainsKey($targetPath)) {
            Write-Change "Adding manifest asset: ProjectTemplate/$($template.ZipName)"

            $assetElem = $manifest.CreateElement("Asset", $ns)
            $assetElem.SetAttribute("Type", "Microsoft.VisualStudio.ProjectTemplate")
            $assetElem.SetAttribute("Source", $nsD, "File")
            $assetElem.SetAttribute("Path", "ProjectTemplates")
            $assetElem.SetAttribute("TargetPath", $nsD, $targetPath)
            $assetsNode.AppendChild($assetElem) | Out-Null
            $modified = $true
        }
    }

    # --- ITEM TEMPLATES ---
    foreach ($template in $ItemTemplates) {
        $targetPath = "ItemTemplates\$($template.ZipName).zip"

        if (-not $existingAssets.ContainsKey($targetPath)) {
            Write-Change "Adding manifest asset: ItemTemplate/$($template.ZipName)"

            $assetElem = $manifest.CreateElement("Asset", $ns)
            $assetElem.SetAttribute("Type", "Microsoft.VisualStudio.ItemTemplate")
            $assetElem.SetAttribute("Source", $nsD, "File")
            $assetElem.SetAttribute("Path", "ItemTemplates")
            $assetElem.SetAttribute("TargetPath", $nsD, $targetPath)
            $assetsNode.AppendChild($assetElem) | Out-Null
            $modified = $true
        }
    }

    if ($modified) {
        if ($PSCmdlet.ShouldProcess($script:Paths.VSIXManifest, "Update VSIX manifest")) {
            # Preserve formatting with XmlWriterSettings
            $settings = New-Object System.Xml.XmlWriterSettings
            $settings.Indent = $true
            $settings.IndentChars = "    "
            $settings.NewLineChars = "`r`n"
            $settings.NewLineHandling = [System.Xml.NewLineHandling]::Replace
            $settings.Encoding = [System.Text.UTF8Encoding]::new($false)

            $writer = [System.Xml.XmlWriter]::Create($script:Paths.VSIXManifest, $settings)
            try {
                $manifest.Save($writer)
            }
            finally {
                $writer.Close()
            }
            Write-Success "VSIX manifest updated"
        }
    } else {
        Write-Info "VSIX manifest already up to date"
    }

    return $true
}

# ==============================================================================
# TEMPLATE BUILDING FUNCTIONS
# ==============================================================================

function Test-ShouldExclude {
    param([string]$Path, [string[]]$Patterns)
    foreach ($pattern in $Patterns) {
        if ($Path -like "*$pattern*") { return $true }
        $name = Split-Path $Path -Leaf
        if ($name -like $pattern) { return $true }
    }
    return $false
}

function Copy-TemplateSource {
    param([string]$SourcePath, [string]$DestPath)

    if (-not (Test-Path $DestPath)) {
        New-Item -ItemType Directory -Path $DestPath -Force | Out-Null
    }

    # Extract RootNamespace from project file for namespace replacement
    $projectFile = Get-ChildItem -Path $SourcePath -Filter "*.csproj" -ErrorAction SilentlyContinue | Select-Object -First 1
    if (-not $projectFile) {
        $projectFile = Get-ChildItem -Path $SourcePath -Filter "*.vbproj" -ErrorAction SilentlyContinue | Select-Object -First 1
    }
    $rootNamespace = $null
    if ($projectFile) {
        $projContent = Get-Content $projectFile.FullName -Raw -ErrorAction SilentlyContinue
        if ($projContent -match '<RootNamespace>([^<]+)</RootNamespace>') {
            $rootNamespace = $matches[1]
        }
        # For SDK-style projects without explicit RootNamespace, use the project file name (without extension)
        # SDK-style projects default the root namespace to the assembly name/project name
        if (-not $rootNamespace) {
            $rootNamespace = [System.IO.Path]::GetFileNameWithoutExtension($projectFile.Name)
        }
    }

    $allFiles = Get-ChildItem -Path $SourcePath -Recurse -File -Force
    $copiedFiles = @()

    foreach ($file in $allFiles) {
        $relativePath = $file.FullName.Substring($SourcePath.Length + 1)
        if (-not (Test-ShouldExclude -Path $relativePath -Patterns $script:ExcludePatterns)) {
            $destFile = Join-Path $DestPath $relativePath
            $destDir = Split-Path $destFile -Parent
            if (-not (Test-Path $destDir)) {
                New-Item -ItemType Directory -Path $destDir -Force | Out-Null
            }

            # For Settings.Designer files, replace hardcoded namespace with template parameter
            if ($file.Name -like "Settings.Designer.*" -and $rootNamespace) {
                $content = Get-Content $file.FullName -Raw -ErrorAction SilentlyContinue
                if ($content) {
                    $content = $content -replace [regex]::Escape("Global.$rootNamespace."), 'Global.$safeprojectname$.'
                    Set-Content -Path $destFile -Value $content -Encoding UTF8 -NoNewline
                } else {
                    Copy-Item $file.FullName -Destination $destFile -Force
                }
            }
            # For project files, replace hardcoded namespace references with template parameter
            elseif ($file.Extension -in @(".csproj", ".vbproj", ".fsproj") -and $rootNamespace) {
                $content = Get-Content $file.FullName -Raw -ErrorAction SilentlyContinue
                if ($content) {
                    # Replace StartupObject namespace reference (e.g., ADDesignExplorerRefresh.Init -> $safeprojectname$.Init)
                    $content = $content -replace "<StartupObject>$([regex]::Escape($rootNamespace))\.", '<StartupObject>$safeprojectname$.'
                    # Replace DocumentationFile references (e.g., ADDesignExplorerRefresh.xml -> $safeprojectname$.xml)
                    $content = $content -replace "<DocumentationFile>$([regex]::Escape($rootNamespace))\.", '<DocumentationFile>$safeprojectname$.'
                    Set-Content -Path $destFile -Value $content -Encoding UTF8 -NoNewline
                } else {
                    Copy-Item $file.FullName -Destination $destFile -Force
                }
            } else {
                Copy-Item $file.FullName -Destination $destFile -Force
            }

            $copiedFiles += @{
                FullPath = $destFile
                RelativePath = $relativePath
                Name = $file.Name
                Extension = $file.Extension
            }
        }
    }

    return $copiedFiles
}

function New-ProjectVSTemplateXml {
    <#
    .SYNOPSIS
        Generates .vstemplate XML for a PROJECT template following Microsoft best practices.

    .DESCRIPTION
        Creates a compliant .vstemplate file per Visual Studio Template Schema Reference.

        Documentation References:
        - Visual Studio Template Schema: https://learn.microsoft.com/en-us/visualstudio/extensibility/visual-studio-template-schema-reference
        - TemplateData Element: https://learn.microsoft.com/en-us/visualstudio/extensibility/templatedata-element-visual-studio-templates
        - ProjectItem Element: https://learn.microsoft.com/en-us/visualstudio/extensibility/projectitem-element-visual-studio-project-templates

        Key Features:
        - OpenInEditor="true" for main source file (auto-opens after project creation)
        - TemplateGroupID for template organization in dialogs
    #>
    param([string]$StagingPath, [hashtable]$Template, [array]$Files)

    $projectFile = $Files | Where-Object { $_.Extension -in @(".csproj", ".vbproj", ".fsproj") } | Select-Object -First 1
    if (-not $projectFile) {
        throw "No project file found in template: $($Template.ZipName)"
    }

    # Find icon file - prefer .ico for VS compatibility
    $iconFile = $Files | Where-Object { $_.Name -like "*icon*" -or $_.Name -like "*logo*" } |
                Where-Object { $_.Extension -in @(".ico", ".png") } | Select-Object -First 1
    $iconName = if ($iconFile) { $iconFile.Name } else { "__TemplateIcon.ico" }

    # Identify the main source file to auto-open after project creation
    # Reference: https://learn.microsoft.com/en-us/visualstudio/extensibility/projectitem-element-visual-studio-project-templates
    $mainSourceExt = if ($Template.Language -eq "CSharp") { ".cs" } else { ".vb" }
    $mainSourceFile = $Files | Where-Object {
        $_.Extension -eq $mainSourceExt -and
        ($_.Name -like "*AddOn*" -or $_.Name -like "*Main*" -or $_.Name -like "*Program*")
    } | Select-Object -First 1

    # Build list of ProjectItem elements, excluding the project file itself
    # The project file is already specified in the Project File= attribute
    $projectItems = @()
    $filesByDir = $Files | Group-Object { Split-Path $_.RelativePath -Parent }

    foreach ($group in $filesByDir) {
        $dirPath = $group.Name
        foreach ($file in $group.Group) {
            # Skip the project file - it's already the Project File= attribute
            if ($file.Name -eq $projectFile.Name) { continue }

            $shouldReplace = $file.Extension -in $script:ReplaceParameterExtensions
            $replaceAttr = if ($shouldReplace) { ' ReplaceParameters="true"' } else { "" }

            # Add OpenInEditor="true" for the main source file
            # This causes VS to open this file automatically after project creation
            $openInEditor = ""
            if ($mainSourceFile -and $file.Name -eq $mainSourceFile.Name -and [string]::IsNullOrEmpty($dirPath)) {
                $openInEditor = ' OpenInEditor="true"'
            }

            if ([string]::IsNullOrEmpty($dirPath)) {
                $projectItems += "      <ProjectItem$replaceAttr$openInEditor TargetFileName=`"$($file.Name)`">$($file.Name)</ProjectItem>"
            }
        }
    }

    $subDirs = $filesByDir | Where-Object { -not [string]::IsNullOrEmpty($_.Name) }
    foreach ($dir in $subDirs) {
        $dirName = $dir.Name
        $folderItems = @()
        foreach ($file in $dir.Group) {
            $shouldReplace = $file.Extension -in $script:ReplaceParameterExtensions
            $replaceAttr = if ($shouldReplace) { ' ReplaceParameters="true"' } else { "" }
            $folderItems += "        <ProjectItem$replaceAttr TargetFileName=`"$($file.Name)`">$($file.Name)</ProjectItem>"
        }
        # Use only Name attribute for folders - TargetFolderName can cause duplication
        $projectItems += "      <Folder Name=`"$dirName`">"
        $projectItems += $folderItems
        $projectItems += "      </Folder>"
    }

    $langTag = $Template.Language.ToLower()

    # Generate compliant .vstemplate following VS Template Schema Reference
    # Version="3.0.0" is required for VS 2012+ features like tags
    $vstemplateContent = @"
<?xml version="1.0" encoding="utf-8"?>
<!--
  Visual Studio Project Template
  Schema Reference: https://learn.microsoft.com/en-us/visualstudio/extensibility/visual-studio-template-schema-reference

  Template Parameters Available:
  - `$safeprojectname`$ : Project name with unsafe characters removed (valid identifier)
  - `$projectname`$     : Original project name as entered by user
  - `$guid1`$-`$guid10`$  : Unique GUIDs for project/assembly identification
  - `$year`$            : Current year (4 digits)
  - `$username`$        : Windows username
  - `$time`$            : Current time

  Full list: https://learn.microsoft.com/en-us/visualstudio/ide/template-parameters
-->
<VSTemplate Version="3.0.0" Type="Project" xmlns="http://schemas.microsoft.com/developer/vstemplate/2005">
  <TemplateData>
    <Name>$($Template.DisplayName)</Name>
    <Description>$($Template.Description)</Description>
    <Icon>$iconName</Icon>
    <ProjectType>$($Template.Language)</ProjectType>
    <SortOrder>$($Template.SortOrder)</SortOrder>
    <TemplateID>$($Template.TemplateID)</TemplateID>
    <TemplateGroupID>$script:TemplateGroupID</TemplateGroupID>
    <LanguageTag>$langTag</LanguageTag>
    <PlatformTag>windows</PlatformTag>
    <ProjectTypeTag>AlibreDesignExtension</ProjectTypeTag>
    <CreateNewFolder>true</CreateNewFolder>
    <DefaultName>$($Template.DefaultName)</DefaultName>
    <ProvideDefaultName>true</ProvideDefaultName>
    <CreateInPlace>true</CreateInPlace>
  </TemplateData>
  <TemplateContent>
    <Project File="$($projectFile.Name)" ReplaceParameters="true" TargetFileName="`$safeprojectname`$$($projectFile.Extension)">
$($projectItems -join "`n")
    </Project>
  </TemplateContent>
</VSTemplate>
"@

    $vstemplatePath = Join-Path $StagingPath "MyTemplate.vstemplate"
    Set-Content -Path $vstemplatePath -Value $vstemplateContent -Encoding UTF8
    return $vstemplatePath
}

function New-ItemVSTemplateXml {
    <#
    .SYNOPSIS
        Generates .vstemplate XML for an ITEM template following Microsoft best practices.

    .DESCRIPTION
        Creates a compliant item template .vstemplate file per Visual Studio Template Schema Reference.

        Documentation References:
        - Visual Studio Template Schema: https://learn.microsoft.com/en-us/visualstudio/extensibility/visual-studio-template-schema-reference
        - Item Templates: https://learn.microsoft.com/en-us/visualstudio/ide/how-to-create-item-templates
        - ProjectItem Element: https://learn.microsoft.com/en-us/visualstudio/extensibility/projectitem-element-visual-studio-item-templates

        Key Features:
        - Type="Item" for Add > New Item dialog integration
        - OpenInEditor="true" for primary source file
        - $safeitemname$ parameter for safe class naming
        - $rootnamespace$ parameter for namespace integration
    #>
    param([string]$StagingPath, [hashtable]$Template)

    $langTag = $Template.Language.ToLower()

    # Build ProjectItem elements for each source file
    # Reference: https://learn.microsoft.com/en-us/visualstudio/extensibility/projectitem-element-visual-studio-item-templates
    $projectItems = @()
    $isFirst = $true
    foreach ($file in $Template.SourceFiles) {
        $shouldReplace = $file.Extension -in $script:ReplaceParameterExtensions
        $replaceAttr = if ($shouldReplace) { ' ReplaceParameters="true"' } else { "" }

        # First source file opens in editor after being added
        # TargetFileName uses $safeitemname$ for proper naming
        $openInEditor = if ($isFirst) { ' OpenInEditor="true"' } else { "" }
        $targetFileName = if ($isFirst) { "`$safeitemname`$$($file.Extension)" } else { $file.Name }

        $projectItems += "    <ProjectItem$replaceAttr$openInEditor TargetFileName=`"$targetFileName`">$($file.Name)</ProjectItem>"
        $isFirst = $false
    }

    # Generate compliant item template .vstemplate
    $vstemplateContent = @"
<?xml version="1.0" encoding="utf-8"?>
<!--
  Visual Studio Item Template
  Schema Reference: https://learn.microsoft.com/en-us/visualstudio/extensibility/visual-studio-template-schema-reference

  Item Template Parameters Available:
  - `$safeitemname`$   : Item name with unsafe characters removed (valid identifier)
  - `$rootnamespace`$  : Root namespace of the containing project
  - `$itemname`$       : Original item name as entered by user
  - `$year`$           : Current year (4 digits)
  - `$username`$       : Windows username
  - `$time`$           : Current time

  Full list: https://learn.microsoft.com/en-us/visualstudio/ide/template-parameters
-->
<VSTemplate Version="3.0.0" Type="Item" xmlns="http://schemas.microsoft.com/developer/vstemplate/2005">
  <TemplateData>
    <Name>$($Template.DisplayName)</Name>
    <Description>$($Template.Description)</Description>
    <Icon>$($Template.IconName)</Icon>
    <ProjectType>$($Template.Language)</ProjectType>
    <LanguageTag>$langTag</LanguageTag>
    <PlatformTag>windows</PlatformTag>
    <ProjectTypeTag>AlibreDesignExtension</ProjectTypeTag>
    <TemplateID>$($Template.TemplateID)</TemplateID>
    <TemplateGroupID>$script:TemplateGroupID</TemplateGroupID>
    <SortOrder>$($Template.SortOrder)</SortOrder>
    <DefaultName>$($Template.DefaultName)</DefaultName>
  </TemplateData>
  <TemplateContent>
$($projectItems -join "`n")
  </TemplateContent>
</VSTemplate>
"@

    $vstemplatePath = Join-Path $StagingPath "$($Template.ZipName).vstemplate"
    Set-Content -Path $vstemplatePath -Value $vstemplateContent -Encoding UTF8
    return $vstemplatePath
}

function New-TemplateZip {
    param([string]$StagingPath, [string]$OutputPath)

    if (Test-Path $OutputPath) { Remove-Item $OutputPath -Force }

    $outputDir = Split-Path $OutputPath -Parent
    if (-not (Test-Path $outputDir)) {
        New-Item -ItemType Directory -Path $outputDir -Force | Out-Null
    }

    Add-Type -AssemblyName System.IO.Compression
    Add-Type -AssemblyName System.IO.Compression.FileSystem

    try {
        $zipMode = [System.IO.Compression.ZipArchiveMode]::Create
        $zipStream = [System.IO.File]::Create($OutputPath)
        $archive = New-Object System.IO.Compression.ZipArchive($zipStream, $zipMode)

        $files = Get-ChildItem -Path $StagingPath -Recurse -File
        $basePath = (Resolve-Path $StagingPath).Path.TrimEnd('\')

        foreach ($file in $files) {
            $relativePath = $file.FullName.Substring($basePath.Length + 1)
            $entryName = $relativePath -replace '\\', '/'
            $compressionLevel = [System.IO.Compression.CompressionLevel]::Optimal
            $entry = $archive.CreateEntry($entryName, $compressionLevel)

            $entryStream = $entry.Open()
            try {
                $fileStream = [System.IO.File]::OpenRead($file.FullName)
                try { $fileStream.CopyTo($entryStream) }
                finally { $fileStream.Close() }
            }
            finally { $entryStream.Close() }
        }
    }
    finally {
        if ($archive) { $archive.Dispose() }
        if ($zipStream) { $zipStream.Close() }
    }

    return $OutputPath
}

function Build-ProjectTemplates {
    param([array]$Templates)

    Write-Section "BUILDING PROJECT TEMPLATES"

    if ($Templates.Count -eq 0) {
        Write-Info "No project templates to build"
        return @()
    }

    $results = @()

    if (-not (Test-Path $script:Paths.Staging)) {
        New-Item -ItemType Directory -Path $script:Paths.Staging -Force | Out-Null
    }
    if (-not (Test-Path $script:Paths.ProjectTemplates)) {
        New-Item -ItemType Directory -Path $script:Paths.ProjectTemplates -Force | Out-Null
    }

    foreach ($template in $Templates) {
        Write-Step "Building: $($template.DisplayName)"

        try {
            $sourcePath = Split-Path $template.ProjectFile -Parent
            $stagingPath = Join-Path $script:Paths.Staging $template.ZipName
            $zipPath = Join-Path $script:Paths.ProjectTemplates "$($template.ZipName).zip"

            if (Test-Path $stagingPath) { Remove-Item $stagingPath -Recurse -Force }

            Write-SubStep "Copying source files..."
            $files = Copy-TemplateSource -SourcePath $sourcePath -DestPath $stagingPath
            Write-SubStep "Copied $($files.Count) files"

            Write-SubStep "Generating .vstemplate..."
            New-ProjectVSTemplateXml -StagingPath $stagingPath -Template $template -Files $files | Out-Null

            Write-SubStep "Creating ZIP..."
            New-TemplateZip -StagingPath $stagingPath -OutputPath $zipPath | Out-Null

            $zipInfo = Get-Item $zipPath
            $zipSizeKB = [math]::Round($zipInfo.Length / 1KB, 2)
            Write-Success "$($template.ZipName).zip ($zipSizeKB KB)"

            $results += @{ Name = $template.ZipName; SizeKB = $zipSizeKB; Success = $true; Type = "Project" }
        }
        catch {
            Write-Failure "Failed: $_"
            $results += @{ Name = $template.ZipName; Error = $_.Exception.Message; Success = $false; Type = "Project" }
        }
    }

    return $results
}

function Build-ItemTemplates {
    param([array]$Templates)

    Write-Section "BUILDING ITEM TEMPLATES"

    if ($Templates.Count -eq 0) {
        Write-Info "No item templates to build"
        return @()
    }

    $results = @()

    if (-not (Test-Path $script:Paths.Staging)) {
        New-Item -ItemType Directory -Path $script:Paths.Staging -Force | Out-Null
    }
    if (-not (Test-Path $script:Paths.ItemTemplates)) {
        New-Item -ItemType Directory -Path $script:Paths.ItemTemplates -Force | Out-Null
    }

    foreach ($template in $Templates) {
        Write-Step "Building: $($template.DisplayName)"

        try {
            $stagingPath = Join-Path $script:Paths.Staging "Items_$($template.ZipName)"
            $zipPath = Join-Path $script:Paths.ItemTemplates "$($template.ZipName).zip"

            if (Test-Path $stagingPath) { Remove-Item $stagingPath -Recurse -Force }
            New-Item -ItemType Directory -Path $stagingPath -Force | Out-Null

            # Copy source files
            Write-SubStep "Copying source files..."
            foreach ($file in $template.SourceFiles) {
                Copy-Item $file.FullName -Destination $stagingPath -Force
            }

            # Copy icon if exists
            if ($template.IconFile) {
                Copy-Item $template.IconFile.FullName -Destination $stagingPath -Force
            }

            Write-SubStep "Generating .vstemplate..."
            New-ItemVSTemplateXml -StagingPath $stagingPath -Template $template | Out-Null

            Write-SubStep "Creating ZIP..."
            New-TemplateZip -StagingPath $stagingPath -OutputPath $zipPath | Out-Null

            $zipInfo = Get-Item $zipPath
            $zipSizeKB = [math]::Round($zipInfo.Length / 1KB, 2)
            Write-Success "$($template.ZipName).zip ($zipSizeKB KB)"

            $results += @{ Name = $template.ZipName; SizeKB = $zipSizeKB; Success = $true; Type = "Item" }
        }
        catch {
            Write-Failure "Failed: $_"
            $results += @{ Name = $template.ZipName; Error = $_.Exception.Message; Success = $false; Type = "Item" }
        }
    }

    return $results
}

# ==============================================================================
# VSIX AND NUGET BUILD
# ==============================================================================

function Find-MSBuild {
    # Get MSBuild search paths from config, with fallback defaults
    $paths = Get-ConfigValue "msbuild.searchPaths" @(
        "C:\Program Files\Microsoft Visual Studio\2026\Enterprise\MSBuild\Current\Bin\MSBuild.exe",
        "C:\Program Files\Microsoft Visual Studio\2026\Professional\MSBuild\Current\Bin\MSBuild.exe",
        "C:\Program Files\Microsoft Visual Studio\2026\Community\MSBuild\Current\Bin\MSBuild.exe",
        "C:\Program Files\Microsoft Visual Studio\2022\Enterprise\MSBuild\Current\Bin\MSBuild.exe",
        "C:\Program Files\Microsoft Visual Studio\2022\Professional\MSBuild\Current\Bin\MSBuild.exe",
        "C:\Program Files\Microsoft Visual Studio\2022\Community\MSBuild\Current\Bin\MSBuild.exe"
    )
    foreach ($path in $paths) {
        if (Test-Path $path) { return $path }
    }
    return $null
}

function Build-VSIX {
    param([string]$MSBuildPath)

    Write-Section "BUILDING VSIX EXTENSION"

    $projectFile = Get-ChildItem -Path $script:Paths.Extension -Filter "*.vbproj" | Select-Object -First 1
    if (-not $projectFile) {
        $projectFile = Get-ChildItem -Path $script:Paths.Extension -Filter "*.csproj" | Select-Object -First 1
    }
    if (-not $projectFile) {
        Write-Failure "No VSIX project found!"
        return $null
    }

    Write-Step "Project: $($projectFile.Name)"
    Write-Step "Configuration: $Configuration"

    if (-not (Test-Path $script:Paths.Temp)) {
        New-Item -ItemType Directory -Path $script:Paths.Temp -Force | Out-Null
    }

    Write-Step "Running MSBuild..."
    Write-Host ""
    & $MSBuildPath $projectFile.FullName /p:Configuration=$Configuration /p:Platform=AnyCPU /t:Restore,Build /v:minimal /nologo | Out-Host
    $exitCode = $LASTEXITCODE
    Write-Host ""

    if ($exitCode -ne 0) {
        Write-Failure "MSBuild failed (exit code $exitCode)"
        return $null
    }

    $vsixFile = Get-ChildItem -Path $script:Paths.BinOutput -Filter "*.vsix" -ErrorAction SilentlyContinue | Select-Object -First 1
    if (-not $vsixFile) {
        Write-Failure "VSIX not found after build!"
        return $null
    }

    $vsixSizeKB = [math]::Round($vsixFile.Length / 1KB, 2)
    Write-Success "VSIX: $($vsixFile.Name) ($vsixSizeKB KB)"
    return $vsixFile.FullName
}

function Get-NuGetExe {
    $nugetPath = Join-Path $script:Paths.Temp "nuget.exe"
    if (Test-Path $nugetPath) { return $nugetPath }

    $nugetInPath = Get-Command nuget.exe -ErrorAction SilentlyContinue
    if ($nugetInPath) { return $nugetInPath.Path }

    Write-SubStep "Downloading nuget.exe..."
    if (-not (Test-Path $script:Paths.Temp)) {
        New-Item -ItemType Directory -Path $script:Paths.Temp -Force | Out-Null
    }
    Invoke-WebRequest -Uri "https://dist.nuget.org/win-x86-commandline/latest/nuget.exe" -OutFile $nugetPath -UseBasicParsing
    return $nugetPath
}

function Build-NuGetPackage {
    Write-Section "BUILDING NUGET PACKAGE"

    if (-not (Test-Path $script:Paths.NuSpec)) {
        Write-Info "NuSpec not found, skipping"
        return $null
    }

    $nugetExe = Get-NuGetExe

    if (-not (Test-Path $script:Paths.NuGetOutput)) {
        New-Item -ItemType Directory -Path $script:Paths.NuGetOutput -Force | Out-Null
    }

    Write-Step "Creating NuGet package..."
    Push-Location $script:Paths.DotnetTemplates
    try {
        & $nugetExe pack $script:Paths.NuSpec -OutputDirectory $script:Paths.NuGetOutput -NoPackageAnalysis 2>&1 | Out-Null
    }
    finally { Pop-Location }

    $nupkgFile = Get-ChildItem -Path $script:Paths.NuGetOutput -Filter "*.nupkg" | Sort-Object LastWriteTime -Descending | Select-Object -First 1
    if (-not $nupkgFile) {
        Write-Failure "NuGet package not found!"
        return $null
    }

    Write-Success "NuGet: $($nupkgFile.Name)"
    return $nupkgFile.FullName
}

# ==============================================================================
# CLEANING
# ==============================================================================

function Clear-BuildOutputs {
    Write-Section "CLEANING BUILD OUTPUTS"

    if (Test-Path $script:Paths.Staging) {
        Write-Step "Removing staging..."
        Remove-Item $script:Paths.Staging -Recurse -Force
    }

    if (Test-Path $script:Paths.ProjectTemplates) {
        Write-Step "Removing project template ZIPs..."
        Get-ChildItem -Path $script:Paths.ProjectTemplates -Filter "*.zip" -ErrorAction SilentlyContinue | Remove-Item -Force
    }

    if (Test-Path $script:Paths.ItemTemplates) {
        Write-Step "Removing item template ZIPs..."
        Get-ChildItem -Path $script:Paths.ItemTemplates -Filter "*.zip" -ErrorAction SilentlyContinue | Remove-Item -Force
    }

    $vsixBin = Join-Path $script:Paths.Extension "bin"
    if (Test-Path $vsixBin) {
        Write-Step "Removing VSIX bin..."
        Remove-Item $vsixBin -Recurse -Force
    }

    $vsixObj = Join-Path $script:Paths.Extension "obj"
    if (Test-Path $vsixObj) {
        Remove-Item $vsixObj -Recurse -Force
    }

    Write-Success "Clean completed"
}

# ==============================================================================
# AUDIT MAP GENERATION
# ==============================================================================

function Export-BuildAuditMap {
    param(
        [array]$ProjectTemplates,
        [array]$ItemTemplates,
        [array]$ProjectResults,
        [array]$ItemResults,
        [string]$VSIXPath,
        [string]$NuPkgPath,
        [TimeSpan]$BuildTime
    )

    $auditDir = $script:Paths.Audit
    if (-not (Test-Path $auditDir)) {
        New-Item -ItemType Directory -Path $auditDir -Force | Out-Null
    }

    $timestamp = Get-Date -Format "yyyy-MM-dd HH:mm:ss"

    $sb = [System.Text.StringBuilder]::new()
    [void]$sb.AppendLine("# Audit Map: build.cmd / Build-All.ps1")
    [void]$sb.AppendLine("")
    [void]$sb.AppendLine("> Template Build System")
    [void]$sb.AppendLine("> Generated: $timestamp")
    [void]$sb.AppendLine("")
    [void]$sb.AppendLine("## Script Chain")
    [void]$sb.AppendLine("")
    [void]$sb.AppendLine('```')
    [void]$sb.AppendLine("build.cmd")
    [void]$sb.AppendLine("    +-- Build-All.ps1")
    [void]$sb.AppendLine("            +-- [1] Template Discovery")
    [void]$sb.AppendLine("            +-- [2] Config File Updates")
    [void]$sb.AppendLine("            +-- [3] Project Template Packaging")
    [void]$sb.AppendLine("            +-- [4] Item Template Packaging")
    [void]$sb.AppendLine("            +-- [5] VSIX Build (MSBuild)")
    [void]$sb.AppendLine("            +-- [6] NuGet Package Creation")
    [void]$sb.AppendLine('```')
    [void]$sb.AppendLine("")
    [void]$sb.AppendLine("---")
    [void]$sb.AppendLine("")

    # Results Summary
    $successProj = ($ProjectResults | Where-Object { $_.Success }).Count
    $successItem = ($ItemResults | Where-Object { $_.Success }).Count
    $failedProj = ($ProjectResults | Where-Object { -not $_.Success }).Count
    $failedItem = ($ItemResults | Where-Object { -not $_.Success }).Count
    $vsixStatus = if ($VSIXPath -and (Test-Path $VSIXPath)) { "BUILT" } else { "SKIPPED" }
    $nupkgStatus = if ($NuPkgPath -and (Test-Path $NuPkgPath)) { "BUILT" } else { "SKIPPED" }
    $overallStatus = if (($failedProj + $failedItem) -eq 0) { "SUCCESS" } else { "FAILED" }

    [void]$sb.AppendLine("## Results Summary")
    [void]$sb.AppendLine("")
    [void]$sb.AppendLine("| Metric | Value |")
    [void]$sb.AppendLine("|--------|-------|")
    [void]$sb.AppendLine("| Project Templates | $successProj built |")
    [void]$sb.AppendLine("| Item Templates | $successItem built |")
    [void]$sb.AppendLine("| VSIX | $vsixStatus |")
    [void]$sb.AppendLine("| NuGet | $nupkgStatus |")
    [void]$sb.AppendLine("| Build Time | $($BuildTime.TotalSeconds.ToString('0.0'))s |")
    [void]$sb.AppendLine("| Status | $overallStatus |")
    [void]$sb.AppendLine("")
    [void]$sb.AppendLine("---")
    [void]$sb.AppendLine("")

    # Input Sources - Project Templates
    [void]$sb.AppendLine("## Input Sources")
    [void]$sb.AppendLine("")
    [void]$sb.AppendLine("### Source Templates")
    [void]$sb.AppendLine("")
    [void]$sb.AppendLine('```')
    [void]$sb.AppendLine("Working/Projects/                           [PROJECT TEMPLATES SOURCE]")

    foreach ($template in $ProjectTemplates) {
        $sourcePath = Split-Path $template.ProjectFile -Parent
        $files = Get-ChildItem -Path $sourcePath -Recurse -File -ErrorAction SilentlyContinue |
                 Where-Object { $_.FullName -notmatch "\\(bin|obj|\.vs)\\" }

        [void]$sb.AppendLine("+-- $($template.FolderName)/")
        foreach ($file in ($files | Select-Object -First 10)) {
            $relPath = $file.FullName.Replace($sourcePath + "\", "")
            [void]$sb.AppendLine("    +-- $relPath")
        }
        if ($files.Count -gt 10) {
            [void]$sb.AppendLine("    +-- ... ($($files.Count - 10) more files)")
        }
    }

    [void]$sb.AppendLine('```')
    [void]$sb.AppendLine("")

    # Working/Items if any
    if ($ItemTemplates.Count -gt 0) {
        [void]$sb.AppendLine('```')
        [void]$sb.AppendLine("Working/Items/                              [ITEM TEMPLATES SOURCE]")
        foreach ($template in $ItemTemplates) {
            [void]$sb.AppendLine("+-- $($template.FolderName)/")
            foreach ($file in $template.SourceFiles) {
                [void]$sb.AppendLine("    +-- $($file.Name)")
            }
            if ($template.IconFile) {
                [void]$sb.AppendLine("    +-- $($template.IconFile.Name)")
            }
        }
        [void]$sb.AppendLine('```')
        [void]$sb.AppendLine("")
    }

    [void]$sb.AppendLine("---")
    [void]$sb.AppendLine("")

    # Output Structure
    [void]$sb.AppendLine("## Output Structure")
    [void]$sb.AppendLine("")
    [void]$sb.AppendLine("### Template ZIP Packages")
    [void]$sb.AppendLine("")
    [void]$sb.AppendLine('```')
    $extRelPath = (Get-ConfigValue "paths.extension" "Extension") + "/$script:ExtensionFolder"
    [void]$sb.AppendLine("$extRelPath/ProjectTemplates/   [PROJECT TEMPLATES]")

    foreach ($result in ($ProjectResults | Where-Object { $_.Success })) {
        [void]$sb.AppendLine("+-- $($result.Name).zip  [$($result.SizeKB) KB]")
    }

    [void]$sb.AppendLine("")
    [void]$sb.AppendLine("$extRelPath/ItemTemplates/      [ITEM TEMPLATES]")

    foreach ($result in ($ItemResults | Where-Object { $_.Success })) {
        [void]$sb.AppendLine("+-- $($result.Name).zip  [$($result.SizeKB) KB]")
    }

    [void]$sb.AppendLine('```')
    [void]$sb.AppendLine("")

    # Final Outputs
    [void]$sb.AppendLine("### Final Outputs")
    [void]$sb.AppendLine("")
    [void]$sb.AppendLine('```')
    [void]$sb.AppendLine("bin/                                        [OUTPUT DIRECTORY]")

    if ($VSIXPath -and (Test-Path $VSIXPath)) {
        $vsixInfo = Get-Item $VSIXPath
        $vsixSizeKB = [math]::Round($vsixInfo.Length / 1KB, 2)
        [void]$sb.AppendLine("+-- $($vsixInfo.Name)  [$vsixSizeKB KB]")
    }

    if ($NuPkgPath -and (Test-Path $NuPkgPath)) {
        $nupkgInfo = Get-Item $NuPkgPath
        $nupkgSizeKB = [math]::Round($nupkgInfo.Length / 1KB, 2)
        [void]$sb.AppendLine("+-- $($nupkgInfo.Name)  [$nupkgSizeKB KB]")
    }

    [void]$sb.AppendLine('```')
    [void]$sb.AppendLine("")
    [void]$sb.AppendLine("---")
    [void]$sb.AppendLine("")

    # Build Results Table
    [void]$sb.AppendLine("## Build Results")
    [void]$sb.AppendLine("")
    [void]$sb.AppendLine("### Project Templates")
    [void]$sb.AppendLine("")
    [void]$sb.AppendLine("| Template | Size | Status |")
    [void]$sb.AppendLine("|----------|------|--------|")

    foreach ($result in $ProjectResults) {
        $status = if ($result.Success) { "PASS" } else { "FAIL" }
        $size = if ($result.SizeKB) { "$($result.SizeKB) KB" } else { "-" }
        [void]$sb.AppendLine("| $($result.Name) | $size | $status |")
    }

    [void]$sb.AppendLine("")

    if ($ItemResults.Count -gt 0) {
        [void]$sb.AppendLine("### Item Templates")
        [void]$sb.AppendLine("")
        [void]$sb.AppendLine("| Template | Size | Status |")
        [void]$sb.AppendLine("|----------|------|--------|")

        foreach ($result in $ItemResults) {
            $status = if ($result.Success) { "PASS" } else { "FAIL" }
            $size = if ($result.SizeKB) { "$($result.SizeKB) KB" } else { "-" }
            [void]$sb.AppendLine("| $($result.Name) | $size | $status |")
        }

        [void]$sb.AppendLine("")
    }

    [void]$sb.AppendLine("---")
    [void]$sb.AppendLine("")
    [void]$sb.AppendLine("## Related Documentation")
    [void]$sb.AppendLine("")
    [void]$sb.AppendLine("- [[BUILD|Build System]]")
    [void]$sb.AppendLine("- [[ARCHITECTURE|Architecture]]")
    [void]$sb.AppendLine("- [[test-pre-audit|Pre-Build Audit]]")
    [void]$sb.AppendLine("- [[test-post-audit|Post-Build Audit]]")
    [void]$sb.AppendLine("")
    [void]$sb.AppendLine("---")
    [void]$sb.AppendLine("")
    [void]$sb.AppendLine("*Generated by Build-All.ps1*")

    $auditPath = Join-Path $auditDir "build-audit.md"
    Set-Content -Path $auditPath -Value $sb.ToString() -Encoding UTF8
    Write-Info "Audit: docs/_audit/build-audit.md"
}

# ==============================================================================
# MAIN EXECUTION
# ==============================================================================

try {
    Write-Banner

    if (-not (Test-Path $script:Paths.Temp)) {
        New-Item -ItemType Directory -Path $script:Paths.Temp -Force | Out-Null
    }

    # Discover all templates
    Write-Section "TEMPLATE DISCOVERY"
    $projectTemplates = Get-DiscoveredProjectTemplates
    $itemTemplates = Get-DiscoveredItemTemplates

    $totalTemplates = $projectTemplates.Count + $itemTemplates.Count
    if ($totalTemplates -eq 0) {
        throw "No templates found in Working/Projects/ or Working/Items/"
    }

    Write-Host ""
    Write-Info "Total: $($projectTemplates.Count) project + $($itemTemplates.Count) item templates"

    # Update configuration files
    Write-Section "UPDATING CONFIGURATION FILES"
    Update-VSIXProject -ProjectTemplates $projectTemplates -ItemTemplates $itemTemplates
    Update-VSIXManifest -ProjectTemplates $projectTemplates -ItemTemplates $itemTemplates
    Update-SolutionFile -ProjectTemplates $projectTemplates
    Update-NuSpec -ProjectTemplates $projectTemplates

    if ($UpdateOnly) {
        Write-Host ""
        Write-Success "Configuration update complete (build skipped)"
        exit 0
    }

    # Clean if requested
    if ($Clean) { Clear-BuildOutputs }

    # Build templates
    $projectResults = Build-ProjectTemplates -Templates $projectTemplates
    $itemResults = Build-ItemTemplates -Templates $itemTemplates

    # Build VSIX
    $vsixPath = $null
    if (-not $SkipVSIX) {
        $msbuild = Find-MSBuild
        if ($msbuild) {
            $vsixPath = Build-VSIX -MSBuildPath $msbuild
        } else {
            Write-Info "MSBuild not found, skipping VSIX"
        }
    }

    # Build NuGet
    $nupkgPath = $null
    if (-not $SkipNuGet) {
        $nupkgPath = Build-NuGetPackage
    }

    # Summary
    $elapsed = (Get-Date) - $script:StartTime

    # Generate build audit map
    Export-BuildAuditMap `
        -ProjectTemplates $projectTemplates `
        -ItemTemplates $itemTemplates `
        -ProjectResults $projectResults `
        -ItemResults $itemResults `
        -VSIXPath $vsixPath `
        -NuPkgPath $nupkgPath `
        -BuildTime $elapsed

    Write-Host ""
    Write-Host ("=" * 78) -ForegroundColor Green
    Write-Host "  BUILD COMPLETE" -ForegroundColor Green
    Write-Host ("=" * 78) -ForegroundColor Green
    Write-Host ""

    $successProj = ($projectResults | Where-Object { $_.Success }).Count
    $successItem = ($itemResults | Where-Object { $_.Success }).Count

    Write-Host "  Project Templates: $successProj built" -ForegroundColor White
    foreach ($t in ($projectResults | Where-Object { $_.Success })) {
        Write-Host "    - $($t.Name).zip ($($t.SizeKB) KB)" -ForegroundColor Gray
    }

    Write-Host ""
    Write-Host "  Item Templates: $successItem built" -ForegroundColor White
    foreach ($t in ($itemResults | Where-Object { $_.Success })) {
        Write-Host "    - $($t.Name).zip ($($t.SizeKB) KB)" -ForegroundColor Gray
    }

    Write-Host ""
    if ($vsixPath) { Write-Host "  VSIX: $(Split-Path $vsixPath -Leaf)" -ForegroundColor White }
    if ($nupkgPath) { Write-Host "  NuGet: $(Split-Path $nupkgPath -Leaf)" -ForegroundColor White }

    Write-Host ""
    Write-Host "  Build Time: $($elapsed.TotalSeconds.ToString('0.0')) seconds" -ForegroundColor DarkGray

    Write-Host ""
    Write-Host "  Reports:" -ForegroundColor White
    $auditPath = Join-Path $script:Paths.Audit "build-audit.md"
    Write-Host "    - $auditPath" -ForegroundColor Gray
    Write-Host "    - $script:LogPath" -ForegroundColor Gray
    Write-Host ""

    Stop-Transcript | Out-Null
}
catch {
    Write-Host ""
    Write-Host "BUILD FAILED: $_" -ForegroundColor Red
    Write-Host $_.ScriptStackTrace -ForegroundColor DarkRed
    Stop-Transcript | Out-Null
    exit 1
}
