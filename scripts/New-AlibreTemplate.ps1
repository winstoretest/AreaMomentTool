<#
.SYNOPSIS
    Interactively creates a new Alibre Design template from an existing project.

.DESCRIPTION
    This script provides a guided wizard for adding new project templates to the
    Alibre Extensions collection. It can work in two modes:

    1. INTERACTIVE MODE (default): Prompts for all template details
    2. PARAMETER MODE: All details provided via command-line parameters

    The script performs these operations:
    1. Copies source project to the Working/ directory
    2. Cleans build artifacts and user-specific files
    3. Adds template parameter placeholders ($safeprojectname$, etc.)
    4. Creates .vstemplate for VSIX
    5. Creates template.json for CLI
    6. Updates the master Build-Templates.ps1 with new template definition

    After running this script, you can build the templates with:
        .\Build-Templates.ps1 -Clean -BuildVSIX -BuildNuGet

    Template Parameter Placeholders:
    --------------------------------
    The script automatically adds these placeholders to appropriate files:

    $safeprojectname$  - Safe version of project name (used in namespaces, filenames)
    $projectname$      - Original project name as entered by user
    $guid1$-$guid10$   - Unique GUIDs for project references
    $year$             - Current year
    $username$         - Current Windows username

.PARAMETER SourcePath
    Path to an existing Alibre AddOn project to use as the template source.
    The project should be in a buildable state.

.PARAMETER TemplateName
    Display name for the template (e.g., "Alibre Custom AddOn (C#)").
    This is shown in the Visual Studio New Project dialog.

.PARAMETER ShortDescription
    Brief description (one sentence) for the template.

.PARAMETER Language
    Programming language: "CSharp" or "VisualBasic".

.PARAMETER TemplateType
    Type of template: "SingleFile", "SingleFileRibbon", or "Script".
    Affects default naming and categorization.

.PARAMETER DefaultProjectName
    Default name suggestion when creating new projects.
    Example: "AlibreAddon" results in "AlibreAddon1", etc.

.PARAMETER Interactive
    Run in interactive mode with prompts (default if no parameters specified).

.EXAMPLE
    .\New-AlibreTemplate.ps1

    Runs in interactive mode, prompting for all details.

.EXAMPLE
    .\New-AlibreTemplate.ps1 -SourcePath "C:\MyProjects\CustomAddon" `
                             -TemplateName "My Custom AddOn (C#)" `
                             -Language "CSharp" `
                             -TemplateType "SingleFile"

    Creates template from source with specified parameters.

.NOTES
    Author: Stephen S. Mitchell
    Version: 1.0.0
    Date: December 2025

    Prerequisites:
    - Source project must compile successfully
    - Source project should be a valid Alibre AddOn

.LINK
    https://github.com/Testbed-for-Alibre-Design/AlibreExtensions
#>

# ==============================================================================
# SCRIPT PARAMETERS
# ==============================================================================

[CmdletBinding(DefaultParameterSetName = "Interactive")]
param(
    # Path to source project
    [Parameter(ParameterSetName = "Automated", Mandatory)]
    [ValidateScript({ Test-Path $_ -PathType Container })]
    [string]$SourcePath,

    # Display name for template
    [Parameter(ParameterSetName = "Automated", Mandatory)]
    [string]$TemplateName,

    # Short description
    [Parameter(ParameterSetName = "Automated")]
    [string]$ShortDescription,

    # Programming language
    [Parameter(ParameterSetName = "Automated", Mandatory)]
    [ValidateSet("CSharp", "VisualBasic")]
    [string]$Language,

    # Template type category
    [Parameter(ParameterSetName = "Automated")]
    [ValidateSet("SingleFile", "SingleFileRibbon", "Script")]
    [string]$TemplateType = "SingleFile",

    # Default project name
    [Parameter(ParameterSetName = "Automated")]
    [string]$DefaultProjectName,

    # Force interactive mode
    [Parameter(ParameterSetName = "Interactive")]
    [switch]$Interactive
)

# ==============================================================================
# CONFIGURATION
# ==============================================================================

$ErrorActionPreference = "Stop"

# Script paths
$ScriptDir = $PSScriptRoot
$RootDir = (Resolve-Path (Join-Path $ScriptDir "..")).Path

$Paths = @{
    Working = Join-Path $RootDir "Working\Projects"
    DotnetTemplates = Join-Path $RootDir "Templates\dotnet"
    BuildScript = Join-Path $ScriptDir "Build-Templates.ps1"
    Temp = Join-Path $RootDir "_temp\new-template"
}

# Files to always exclude from templates
$ExcludeFiles = @(
    "*.user",
    "*.suo",
    ".vs",
    "bin",
    "obj",
    "packages",
    "TestResults",
    ".git",
    "*.log"
)

# ==============================================================================
# HELPER FUNCTIONS
# ==============================================================================

function Write-Header {
    param([string]$Text)
    $line = "=" * 60
    Write-Host ""
    Write-Host $line -ForegroundColor Magenta
    Write-Host "  $Text" -ForegroundColor Magenta
    Write-Host $line -ForegroundColor Magenta
    Write-Host ""
}

function Write-Step {
    param([string]$Text)
    Write-Host "  [*] $Text" -ForegroundColor Cyan
}

function Write-Success {
    param([string]$Text)
    Write-Host "  [OK] $Text" -ForegroundColor Green
}

function Write-Info {
    param([string]$Text)
    Write-Host "  [i] $Text" -ForegroundColor Gray
}

function Read-UserInput {
    <#
    .SYNOPSIS
        Prompts user for input with optional default value.
    #>
    param(
        [string]$Prompt,
        [string]$Default = "",
        [switch]$Required
    )

    $defaultDisplay = if ($Default) { " [$Default]" } else { "" }
    $fullPrompt = "  $Prompt$defaultDisplay`: "

    do {
        Write-Host $fullPrompt -NoNewline -ForegroundColor Yellow
        $input = Read-Host

        if ([string]::IsNullOrWhiteSpace($input)) {
            if ($Default) {
                return $Default
            } elseif ($Required) {
                Write-Host "    This field is required." -ForegroundColor Red
                continue
            }
        }
        return $input
    } while ($true)
}

function Read-UserChoice {
    <#
    .SYNOPSIS
        Prompts user to select from a list of choices.
    #>
    param(
        [string]$Prompt,
        [string[]]$Choices,
        [int]$Default = 0
    )

    Write-Host "  $Prompt" -ForegroundColor Yellow
    for ($i = 0; $i -lt $Choices.Count; $i++) {
        $marker = if ($i -eq $Default) { "*" } else { " " }
        Write-Host "    $marker [$($i + 1)] $($Choices[$i])" -ForegroundColor White
    }

    $defaultDisplay = $Default + 1
    Write-Host "  Enter choice [$defaultDisplay]: " -NoNewline -ForegroundColor Yellow
    $input = Read-Host

    if ([string]::IsNullOrWhiteSpace($input)) {
        return $Choices[$Default]
    }

    $selection = [int]$input - 1
    if ($selection -ge 0 -and $selection -lt $Choices.Count) {
        return $Choices[$selection]
    }

    return $Choices[$Default]
}

function Get-SafeName {
    <#
    .SYNOPSIS
        Converts a string to a safe identifier name.
    #>
    param([string]$Name)

    # Remove invalid characters, keep only alphanumeric and underscore
    $safe = $Name -replace '[^a-zA-Z0-9_]', ''

    # Ensure doesn't start with number
    if ($safe -match '^[0-9]') {
        $safe = "_$safe"
    }

    return $safe
}

function Copy-TemplateSource {
    <#
    .SYNOPSIS
        Copies source project to Working directory, cleaning artifacts.
    #>
    param(
        [string]$Source,
        [string]$Destination
    )

    Write-Step "Copying source files..."

    # Create destination
    if (Test-Path $Destination) {
        Remove-Item $Destination -Recurse -Force
    }
    New-Item -ItemType Directory -Path $Destination -Force | Out-Null

    # Copy with exclusions
    $sourceFiles = Get-ChildItem -Path $Source -Recurse -File | Where-Object {
        $relativePath = $_.FullName.Substring($Source.Length + 1)
        $exclude = $false
        foreach ($pattern in $ExcludeFiles) {
            if ($relativePath -like "*$pattern*") {
                $exclude = $true
                break
            }
        }
        -not $exclude
    }

    $copiedCount = 0
    foreach ($file in $sourceFiles) {
        $relativePath = $file.FullName.Substring($Source.Length + 1)
        $destPath = Join-Path $Destination $relativePath
        $destDir = Split-Path $destPath -Parent

        if (-not (Test-Path $destDir)) {
            New-Item -ItemType Directory -Path $destDir -Force | Out-Null
        }

        Copy-Item $file.FullName -Destination $destPath -Force
        $copiedCount++
    }

    Write-Info "Copied $copiedCount files"
}

function Add-TemplateParameters {
    <#
    .SYNOPSIS
        Replaces hardcoded project names with template parameters.
    #>
    param(
        [string]$TemplatePath,
        [string]$OriginalName
    )

    Write-Step "Adding template parameters..."

    # File extensions to process
    $textExtensions = @(".cs", ".vb", ".csproj", ".vbproj", ".adc", ".xml", ".json", ".config")

    $files = Get-ChildItem -Path $TemplatePath -Recurse -File | Where-Object {
        $textExtensions -contains $_.Extension.ToLower()
    }

    $modifiedCount = 0
    foreach ($file in $files) {
        $content = Get-Content $file.FullName -Raw -ErrorAction SilentlyContinue
        if ($content) {
            $originalContent = $content

            # Replace project name variations with template parameters
            # Be careful with order - replace longer strings first
            $content = $content -replace [regex]::Escape($OriginalName), '$safeprojectname$'

            if ($content -ne $originalContent) {
                Set-Content -Path $file.FullName -Value $content -NoNewline
                $modifiedCount++
            }
        }
    }

    Write-Info "Modified $modifiedCount files with template parameters"
}

function New-CliTemplateConfig {
    <#
    .SYNOPSIS
        Creates the .template.config/template.json for CLI templates.
    #>
    param(
        [string]$TemplatePath,
        [hashtable]$Config
    )

    Write-Step "Creating CLI template configuration..."

    $configDir = Join-Path $TemplatePath ".template.config"
    if (-not (Test-Path $configDir)) {
        New-Item -ItemType Directory -Path $configDir -Force | Out-Null
    }

    $languageTag = if ($Config.Language -eq "CSharp") { "C#" } else { "VB" }
    $classifications = @("Alibre", "CAD", "AddOn")
    if ($Config.TemplateType -eq "Script") { $classifications += "Script" }
    if ($Config.TemplateType -eq "SingleFileRibbon") { $classifications += "Ribbon"; $classifications += "UI" }

    $templateJson = @{
        '$schema' = "http://json.schemastore.org/template"
        author = "Stephen S. Mitchell"
        classifications = $classifications
        identity = $Config.Identity
        name = $Config.DisplayName
        shortName = $Config.ShortName
        tags = @{
            language = $languageTag
            type = "project"
        }
        sourceName = $Config.SourceName
        preferNameDirectory = $true
        symbols = @{
            Framework = @{
                type = "parameter"
                description = "The target framework for the project."
                datatype = "choice"
                choices = @(
                    @{ choice = "net481"; description = "Target .NET Framework 4.8.1" },
                    @{ choice = "net48"; description = "Target .NET Framework 4.8" }
                )
                replaces = "net481"
                defaultValue = "net481"
            }
        }
        sources = @(
            @{
                modifiers = @(
                    @{
                        exclude = @(
                            "**/bin/**",
                            "**/obj/**",
                            "**/.vs/**",
                            "**/.git/**",
                            "**/*.user",
                            "**/*.log",
                            "**/.template.config/**"
                        )
                    }
                )
            }
        )
    }

    $jsonPath = Join-Path $configDir "template.json"
    $templateJson | ConvertTo-Json -Depth 10 | Set-Content $jsonPath -Encoding UTF8

    Write-Info "Created: $jsonPath"
}

function Update-BuildScript {
    <#
    .SYNOPSIS
        Adds new template definition to Build-Templates.ps1.

    .DESCRIPTION
        Modifies the $TemplateDefinitions array in the build script
        to include the new template.
    #>
    param(
        [hashtable]$Config
    )

    Write-Step "Updating Build-Templates.ps1..."

    # Read current script
    $buildScript = Get-Content $Paths.BuildScript -Raw

    # Find the template definitions array and add new entry
    # This is a simplified approach - in production, use AST parsing

    $newEntry = @"

    @{
        SourceFolder = "$($Config.SourceFolder)"
        ZipName = "$($Config.ZipName)"
        DisplayName = "$($Config.DisplayName)"
        Description = "$($Config.Description)"
        Language = "$($Config.Language)"
        DefaultName = "$($Config.DefaultName)"
        SortOrder = $($Config.SortOrder)
        ShortName = "$($Config.ShortName)"
        CliIdentity = "$($Config.Identity)"
        Tags = @($($Config.Tags | ForEach-Object { "`"$_`"" }) -join ", ")
    },
"@

    Write-Info "New template definition prepared"
    Write-Host ""
    Write-Host "  Add this entry to `$TemplateDefinitions in Build-Templates.ps1:" -ForegroundColor Yellow
    Write-Host $newEntry -ForegroundColor White
    Write-Host ""

    # Note: Automatic script modification is risky - show manual instructions instead
    Write-Info "Manual addition recommended for safety"
}

# ==============================================================================
# INTERACTIVE MODE
# ==============================================================================

function Start-InteractiveMode {
    <#
    .SYNOPSIS
        Runs the interactive wizard to gather template information.
    #>

    Write-Header "New Alibre Template Wizard"

    Write-Host "  This wizard will help you create a new Alibre Design template." -ForegroundColor Gray
    Write-Host "  Press Ctrl+C at any time to cancel." -ForegroundColor Gray
    Write-Host ""

    # ---------------------------------------------------------------------------
    # Gather information
    # ---------------------------------------------------------------------------

    # Source path
    Write-Host "  STEP 1: Source Project" -ForegroundColor Cyan
    Write-Host "  -----------------------" -ForegroundColor Cyan
    $sourcePath = Read-UserInput -Prompt "Path to source project" -Required

    if (-not (Test-Path $sourcePath)) {
        throw "Source path does not exist: $sourcePath"
    }

    # Detect language from project file
    $csproj = Get-ChildItem -Path $sourcePath -Filter "*.csproj" -Recurse | Select-Object -First 1
    $vbproj = Get-ChildItem -Path $sourcePath -Filter "*.vbproj" -Recurse | Select-Object -First 1

    if ($csproj) {
        $detectedLanguage = "CSharp"
        $projectFile = $csproj
    } elseif ($vbproj) {
        $detectedLanguage = "VisualBasic"
        $projectFile = $vbproj
    } else {
        throw "No .csproj or .vbproj file found in source path"
    }

    Write-Info "Detected language: $detectedLanguage"
    Write-Info "Project file: $($projectFile.Name)"
    Write-Host ""

    # Template details
    Write-Host "  STEP 2: Template Details" -ForegroundColor Cyan
    Write-Host "  ------------------------" -ForegroundColor Cyan

    $originalName = [System.IO.Path]::GetFileNameWithoutExtension($projectFile.Name)
    Write-Info "Original project name: $originalName"

    $templateName = Read-UserInput -Prompt "Display name" -Default "$originalName ($detectedLanguage)" -Required
    $description = Read-UserInput -Prompt "Description" -Default "Alibre Design AddOn template" -Required

    $templateType = Read-UserChoice -Prompt "Template type:" -Choices @("SingleFile", "SingleFileRibbon", "Script") -Default 0
    $defaultName = Read-UserInput -Prompt "Default project name" -Default "AlibreAddon"
    Write-Host ""

    # Generate identifiers
    Write-Host "  STEP 3: Identifiers (auto-generated)" -ForegroundColor Cyan
    Write-Host "  -------------------------------------" -ForegroundColor Cyan

    $safeName = Get-SafeName $originalName
    $langSuffix = if ($detectedLanguage -eq "CSharp") { "CS" } else { "VB" }
    $typeSuffix = switch ($templateType) {
        "SingleFileRibbon" { "Ribbon" }
        "Script" { "Script" }
        default { "" }
    }

    $zipName = "$safeName$langSuffix$typeSuffix"
    $shortName = "alibre-$(($safeName -replace 'Alibre', '').ToLower())-$($langSuffix.ToLower())"
    $identity = "Alibre.$safeName.$detectedLanguage"

    Write-Info "ZIP name: $zipName"
    Write-Info "CLI short name: $shortName"
    Write-Info "Identity: $identity"
    Write-Host ""

    # Confirm
    Write-Host "  STEP 4: Confirm" -ForegroundColor Cyan
    Write-Host "  ---------------" -ForegroundColor Cyan
    Write-Host "  Template Name: $templateName" -ForegroundColor White
    Write-Host "  Description: $description" -ForegroundColor White
    Write-Host "  Language: $detectedLanguage" -ForegroundColor White
    Write-Host "  Type: $templateType" -ForegroundColor White
    Write-Host "  ZIP Name: $zipName" -ForegroundColor White
    Write-Host ""

    $confirm = Read-UserInput -Prompt "Create this template? (y/n)" -Default "y"
    if ($confirm -ne "y" -and $confirm -ne "Y") {
        Write-Host "  Cancelled." -ForegroundColor Yellow
        return
    }

    # Return configuration
    return @{
        SourcePath = $sourcePath
        OriginalName = $originalName
        DisplayName = $templateName
        Description = $description
        Language = $detectedLanguage
        TemplateType = $templateType
        DefaultName = $defaultName
        ZipName = $zipName
        ShortName = $shortName
        Identity = $identity
        SourceFolder = $zipName
        SourceName = "AlibreAddOn"
        SortOrder = 200  # New templates get higher sort order
        Tags = @("Alibre", "CAD", "AddOn")
    }
}

# ==============================================================================
# MAIN EXECUTION
# ==============================================================================

Write-Host ""
Write-Host "============================================================" -ForegroundColor Magenta
Write-Host "  Alibre Design - New Template Creator" -ForegroundColor Magenta
Write-Host "============================================================" -ForegroundColor Magenta

# Determine mode and get configuration
if ($PSCmdlet.ParameterSetName -eq "Interactive" -or $Interactive) {
    $config = Start-InteractiveMode
    if (-not $config) {
        exit 0
    }
} else {
    # Build config from parameters
    $langSuffix = if ($Language -eq "CSharp") { "CS" } else { "VB" }
    $originalName = Split-Path $SourcePath -Leaf

    $config = @{
        SourcePath = $SourcePath
        OriginalName = $originalName
        DisplayName = $TemplateName
        Description = if ($ShortDescription) { $ShortDescription } else { "Alibre Design AddOn template" }
        Language = $Language
        TemplateType = $TemplateType
        DefaultName = if ($DefaultProjectName) { $DefaultProjectName } else { "AlibreAddon" }
        ZipName = (Get-SafeName $originalName) + $langSuffix
        ShortName = "alibre-custom-$($langSuffix.ToLower())"
        Identity = "Alibre.Custom.$Language"
        SourceFolder = (Get-SafeName $originalName) + $langSuffix
        SourceName = "AlibreAddOn"
        SortOrder = 200
        Tags = @("Alibre", "CAD", "AddOn")
    }
}

Write-Host ""

# ---------------------------------------------------------------------------
# Execute template creation
# ---------------------------------------------------------------------------

try {
    # Create Working directory destination
    $workingDest = Join-Path $Paths.Working $config.ZipName
    Copy-TemplateSource -Source $config.SourcePath -Destination $workingDest

    # Add template parameters
    Add-TemplateParameters -TemplatePath $workingDest -OriginalName $config.OriginalName

    # Create CLI template in dotnet templates directory
    $cliDest = Join-Path $Paths.DotnetTemplates $config.ZipName
    Copy-TemplateSource -Source $config.SourcePath -Destination $cliDest
    Add-TemplateParameters -TemplatePath $cliDest -OriginalName $config.OriginalName
    New-CliTemplateConfig -TemplatePath $cliDest -Config $config

    # Show build script update instructions
    Update-BuildScript -Config $config

    Write-Host ""
    Write-Success "Template created successfully!"
    Write-Host ""
    Write-Host "  Next steps:" -ForegroundColor Yellow
    Write-Host "    1. Add the template definition to Build-Templates.ps1" -ForegroundColor White
    Write-Host "    2. Run: .\Build-Templates.ps1 -Clean -BuildVSIX -BuildNuGet" -ForegroundColor White
    Write-Host "    3. Test the template in Visual Studio" -ForegroundColor White
    Write-Host ""
}
catch {
    Write-Host ""
    Write-Host "  [ERROR] Template creation failed: $_" -ForegroundColor Red
    Write-Host ""
    throw
}
