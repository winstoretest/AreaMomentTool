<#
.SYNOPSIS
    Generates a Visual Studio .vstemplate file from a source project.

.DESCRIPTION
    This script creates a properly formatted .vstemplate XML file that Visual Studio
    uses to understand how to create new projects from a template.

    The .vstemplate file contains:
    - Template metadata (name, description, icon, language)
    - Project structure definition
    - File list with parameter replacement settings
    - Sorting and grouping information for the New Project dialog

    Visual Studio Template Parameter Reference:
    -------------------------------------------
    These parameters are replaced when a user creates a new project:

    $projectname$       - The project name entered by the user
    $safeprojectname$   - Project name with invalid characters removed (safe for identifiers)
    $guid1$ - $guid10$  - Unique GUIDs generated for the project
    $time$              - Current time in DD/MM/YYYY HH:MM:SS format
    $year$              - Current year as four digits
    $username$          - Current Windows user name
    $userdomain$        - Current Windows domain name
    $machinename$       - Name of the computer
    $clrversion$        - Current CLR version
    $registeredorganization$ - Organization from Windows registration
    $targetframeworkversion$ - Target .NET Framework version

.PARAMETER SourcePath
    Path to the directory containing the template source files.
    This should be a staging directory with all files ready to package.

.PARAMETER TemplateName
    Display name for the template (shown in Visual Studio New Project dialog).

.PARAMETER Description
    Detailed description of the template (shown in VS when template is selected).

.PARAMETER Language
    Programming language: "CSharp" or "VisualBasic".
    Determines which project type filter the template appears under.

.PARAMETER DefaultName
    Default project name suggestion when user creates new project.
    Example: "AlibreAddon" results in "AlibreAddon1", "AlibreAddon2", etc.

.PARAMETER SortOrder
    Numeric sort order for template in the list (lower = higher priority).
    Alibre templates use 100-199 range.

.PARAMETER TemplateID
    Unique identifier for this template. Used internally by VS.
    Typically matches the ZIP file name without extension.

.PARAMETER GroupID
    Template group ID for categorization. Default: "AlibreDesign".
    All Alibre templates share this group so they appear together.

.PARAMETER IconFile
    Name of the icon file to use. Default: "__TemplateIcon.ico".
    This icon appears in the New Project dialog.

.EXAMPLE
    .\New-VSTemplate.ps1 -SourcePath "C:\temp\MyTemplate" `
                         -TemplateName "My Alibre AddOn" `
                         -Description "A custom Alibre Design AddOn template" `
                         -Language "CSharp" `
                         -DefaultName "MyAddon" `
                         -SortOrder 150 `
                         -TemplateID "MyAlibreAddon"

.NOTES
    Author: Stephen S. Mitchell
    Version: 1.0.0
    Date: December 2025

    The generated .vstemplate file follows the Visual Studio 2017+ schema.
    For more information on vstemplate format, see:
    https://docs.microsoft.com/en-us/visualstudio/extensibility/visual-studio-template-schema-reference

.LINK
    https://github.com/Testbed-for-Alibre-Design/AlibreExtensions
#>

# ==============================================================================
# SCRIPT PARAMETERS
# ==============================================================================

[CmdletBinding()]
param(
    # Path to the template source files
    [Parameter(Mandatory)]
    [ValidateScript({ Test-Path $_ -PathType Container })]
    [string]$SourcePath,

    # Display name for the template
    [Parameter(Mandatory)]
    [string]$TemplateName,

    # Template description
    [Parameter(Mandatory)]
    [string]$Description,

    # Programming language (CSharp or VisualBasic)
    [Parameter(Mandatory)]
    [ValidateSet("CSharp", "VisualBasic")]
    [string]$Language,

    # Default project name
    [Parameter(Mandatory)]
    [string]$DefaultName,

    # Sort order in template list
    [Parameter(Mandatory)]
    [int]$SortOrder,

    # Unique template identifier
    [Parameter(Mandatory)]
    [string]$TemplateID,

    # Template group ID for categorization
    [string]$GroupID = "AlibreDesign",

    # Icon file name
    [string]$IconFile = "__TemplateIcon.ico"
)

# ==============================================================================
# CONFIGURATION
# ==============================================================================

$ErrorActionPreference = "Stop"

# File extensions that should have parameter replacement enabled
# When VS creates a project, it replaces $projectname$, $guid1$, etc. in these files
$ReplaceParameterExtensions = @(
    ".cs",      # C# source files
    ".vb",      # VB.NET source files
    ".csproj",  # C# project files
    ".vbproj",  # VB project files
    ".adc",     # Alibre Design Configuration files
    ".xml",     # XML files
    ".config",  # Configuration files
    ".json",    # JSON files (project.json, launch settings, etc.)
    ".py",      # Python scripts (for IronPython templates)
    ".txt",     # Text files (README, LICENSE, etc.)
    ".md"       # Markdown files
)

# Files/folders to exclude from the template
# These are either build artifacts or handled specially
$ExcludePatterns = @(
    "bin",
    "obj",
    ".vs",
    ".git",
    "*.user",
    "*.suo",
    "TestResults",
    "packages",
    ".template.config",
    "MyTemplate.vstemplate"  # Don't include existing vstemplate
)

# ==============================================================================
# HELPER FUNCTIONS
# ==============================================================================

function Test-ShouldExclude {
    <#
    .SYNOPSIS
        Determines if a file or folder should be excluded from the template.

    .PARAMETER Path
        The path to check.

    .OUTPUTS
        $true if the path should be excluded, $false otherwise.
    #>
    param([string]$Path)

    foreach ($pattern in $ExcludePatterns) {
        if ($Path -like "*$pattern*") {
            return $true
        }
    }
    return $false
}

function Test-ShouldReplaceParameters {
    <#
    .SYNOPSIS
        Determines if a file should have VS template parameters replaced.

    .DESCRIPTION
        Files with certain extensions contain text that may include template
        parameters like $projectname$ or $safeprojectname$. When VS creates
        a project from the template, it replaces these with actual values.

    .PARAMETER Extension
        The file extension (including the dot).

    .OUTPUTS
        $true if parameters should be replaced, $false otherwise.
    #>
    param([string]$Extension)

    return $ReplaceParameterExtensions -contains $Extension.ToLower()
}

function Get-ProjectFile {
    <#
    .SYNOPSIS
        Finds the main project file in a directory.

    .PARAMETER Path
        Directory to search.

    .PARAMETER Language
        Programming language to determine file extension.

    .OUTPUTS
        FileInfo object for the project file, or $null if not found.
    #>
    param(
        [string]$Path,
        [string]$Language
    )

    $extension = if ($Language -eq "CSharp") { "*.csproj" } else { "*.vbproj" }
    return Get-ChildItem -Path $Path -Filter $extension -File | Select-Object -First 1
}

function Build-ProjectItemXml {
    <#
    .SYNOPSIS
        Creates XML for a ProjectItem element.

    .DESCRIPTION
        ProjectItem elements in a vstemplate define individual files that
        should be included in the generated project.

    .PARAMETER FileName
        Name of the file.

    .PARAMETER TargetFileName
        Target filename (can include parameters like $safeprojectname$).

    .PARAMETER ReplaceParameters
        Whether VS should replace template parameters in this file.

    .PARAMETER Indent
        Number of spaces to indent the XML.

    .OUTPUTS
        XML string for the ProjectItem element.
    #>
    param(
        [string]$FileName,
        [string]$TargetFileName,
        [bool]$ReplaceParameters,
        [int]$Indent = 6
    )

    $spaces = " " * $Indent
    $replaceAttr = if ($ReplaceParameters) { ' ReplaceParameters="true"' } else { "" }

    return "$spaces<ProjectItem$replaceAttr TargetFileName=`"$TargetFileName`">$FileName</ProjectItem>"
}

function Build-FolderXml {
    <#
    .SYNOPSIS
        Creates XML for a Folder element with its contents.

    .DESCRIPTION
        Folder elements define subdirectories in the project structure.
        They contain ProjectItem elements for the files within.

    .PARAMETER FolderPath
        Path to the folder.

    .PARAMETER FolderName
        Name of the folder (for the element attributes).

    .PARAMETER BasePath
        Base path for calculating relative paths.

    .PARAMETER Indent
        Number of spaces to indent the XML.

    .OUTPUTS
        XML string for the Folder element and its contents.
    #>
    param(
        [string]$FolderPath,
        [string]$FolderName,
        [string]$BasePath,
        [int]$Indent = 6
    )

    $spaces = " " * $Indent
    $innerSpaces = " " * ($Indent + 2)
    $xml = @()

    $xml += "$spaces<Folder Name=`"$FolderName`" TargetFolderName=`"$FolderName`">"

    # Get files in this folder
    $files = Get-ChildItem -Path $FolderPath -File | Where-Object {
        -not (Test-ShouldExclude $_.Name)
    }

    foreach ($file in $files) {
        $replaceParams = Test-ShouldReplaceParameters $file.Extension
        $itemXml = Build-ProjectItemXml `
            -FileName $file.Name `
            -TargetFileName $file.Name `
            -ReplaceParameters $replaceParams `
            -Indent ($Indent + 2)
        $xml += $itemXml
    }

    # Recursively handle subfolders
    $subfolders = Get-ChildItem -Path $FolderPath -Directory | Where-Object {
        -not (Test-ShouldExclude $_.Name)
    }

    foreach ($subfolder in $subfolders) {
        $subXml = Build-FolderXml `
            -FolderPath $subfolder.FullName `
            -FolderName $subfolder.Name `
            -BasePath $BasePath `
            -Indent ($Indent + 2)
        $xml += $subXml
    }

    $xml += "$spaces</Folder>"

    return $xml -join "`r`n"
}

# ==============================================================================
# MAIN LOGIC
# ==============================================================================

Write-Verbose "Generating vstemplate for: $TemplateName"
Write-Verbose "Source path: $SourcePath"

# ---------------------------------------------------------------------------
# STEP 1: Find the project file
# ---------------------------------------------------------------------------
# The project file (.csproj or .vbproj) is the anchor of the template.
# VS needs to know which file to use as the main project.

$projectFile = Get-ProjectFile -Path $SourcePath -Language $Language

if (-not $projectFile) {
    throw "No project file found in $SourcePath for language $Language"
}

Write-Verbose "Found project file: $($projectFile.Name)"

# ---------------------------------------------------------------------------
# STEP 2: Collect files at the root level
# ---------------------------------------------------------------------------
# These are files that sit directly in the project folder, not in subfolders

$rootFiles = Get-ChildItem -Path $SourcePath -File | Where-Object {
    -not (Test-ShouldExclude $_.Name) -and
    $_.Name -ne $projectFile.Name -and  # Project file handled separately
    $_.Name -ne $IconFile               # Icon file referenced in metadata
}

Write-Verbose "Found $($rootFiles.Count) root-level files"

# ---------------------------------------------------------------------------
# STEP 3: Collect subdirectories
# ---------------------------------------------------------------------------
# Subfolders like "scripts" or "Properties" need their own Folder elements

$subfolders = Get-ChildItem -Path $SourcePath -Directory | Where-Object {
    -not (Test-ShouldExclude $_.Name)
}

Write-Verbose "Found $($subfolders.Count) subfolders"

# ---------------------------------------------------------------------------
# STEP 4: Build the ProjectItem XML for root files
# ---------------------------------------------------------------------------

$projectItemsXml = @()

foreach ($file in $rootFiles) {
    $replaceParams = Test-ShouldReplaceParameters $file.Extension

    # Special handling for .adc files - they often contain the project name
    $targetFileName = $file.Name
    if ($file.Extension -eq ".adc") {
        # Replace the hardcoded project name with the template parameter
        # So "AlibreAddon.adc" becomes "$safeprojectname$.adc"
        $targetFileName = "`$safeprojectname`$$($file.Extension)"
    }

    $itemXml = Build-ProjectItemXml `
        -FileName $file.Name `
        -TargetFileName $targetFileName `
        -ReplaceParameters $replaceParams

    $projectItemsXml += $itemXml
}

# ---------------------------------------------------------------------------
# STEP 5: Build the Folder XML for subdirectories
# ---------------------------------------------------------------------------

$foldersXml = @()

foreach ($folder in $subfolders) {
    $folderXml = Build-FolderXml `
        -FolderPath $folder.FullName `
        -FolderName $folder.Name `
        -BasePath $SourcePath

    $foldersXml += $folderXml
}

# ---------------------------------------------------------------------------
# STEP 6: Assemble the complete vstemplate XML
# ---------------------------------------------------------------------------
# The vstemplate has two main sections:
#   - TemplateData: Metadata about the template
#   - TemplateContent: The actual project structure and files

$projectExtension = $projectFile.Extension
$projectItemsStr = $projectItemsXml -join "`r`n"
$foldersStr = $foldersXml -join "`r`n"

# Combine items and folders, with proper line breaks
$contentItems = @()
if ($projectItemsStr) { $contentItems += $projectItemsStr }
if ($foldersStr) { $contentItems += $foldersStr }
$allContentStr = $contentItems -join "`r`n"

# The complete vstemplate document
$vstemplate = @"
<?xml version="1.0" encoding="utf-8"?>
<!--
    Visual Studio Project Template
    ==============================
    Generated by: New-VSTemplate.ps1
    Generated on: $(Get-Date -Format "yyyy-MM-dd HH:mm:ss")

    This file defines how Visual Studio creates new projects from this template.

    Template: $TemplateName
    Language: $Language
    Template ID: $TemplateID

    DO NOT EDIT MANUALLY - Regenerate using Build-Templates.ps1
-->
<VSTemplate Version="3.0.0" Type="Project"
            xmlns="http://schemas.microsoft.com/developer/vstemplate/2005"
            xmlns:sdk="http://schemas.microsoft.com/developer/vstemplate-sdkextension/2010">

  <!-- ========================================================================
       TEMPLATE METADATA
       This section defines how the template appears in VS New Project dialog
       ======================================================================== -->
  <TemplateData>
    <!-- Display name shown in the template list -->
    <Name>$TemplateName</Name>

    <!-- Description shown when template is selected -->
    <Description>$Description</Description>

    <!-- Icon displayed next to the template name -->
    <Icon>$IconFile</Icon>

    <!-- Project type determines which language filter shows this template -->
    <!-- Valid values: CSharp, VisualBasic, FSharp, etc. -->
    <ProjectType>$Language</ProjectType>

    <!-- Sort order within the template list (lower numbers appear first) -->
    <SortOrder>$SortOrder</SortOrder>

    <!-- Group ID for organizing related templates together -->
    <!-- All Alibre templates use "AlibreDesign" to appear in same category -->
    <TemplateGroupID>$GroupID</TemplateGroupID>

    <!-- Unique identifier for this template -->
    <TemplateID>$TemplateID</TemplateID>

    <!-- Language tag for filtering (must match ProjectType) -->
    <LanguageTag>$Language</LanguageTag>

    <!-- Platform tag for filtering -->
    <PlatformTag>Windows</PlatformTag>

    <!-- Project type tags for additional filtering -->
    <!-- These help users find templates via the "All project types" filter -->
    <ProjectTypeTag>AlibreDesignExtension</ProjectTypeTag>

    <!-- Default project name - VS appends numbers for uniqueness -->
    <DefaultName>$DefaultName</DefaultName>

    <!-- Enable/disable various New Project dialog features -->
    <ProvideDefaultName>true</ProvideDefaultName>
    <CreateNewFolder>true</CreateNewFolder>
    <LocationField>Enabled</LocationField>
    <EnableLocationBrowseButton>true</EnableLocationBrowseButton>

    <!-- CreateInPlace=true means project is created directly in selected folder -->
    <!-- (vs creating a subdirectory with the project name) -->
    <CreateInPlace>true</CreateInPlace>
  </TemplateData>

  <!-- ========================================================================
       TEMPLATE CONTENT
       This section defines the project structure and files
       ======================================================================== -->
  <TemplateContent>
    <!--
        Project element defines the main project file.
        - File: The project file to use as template
        - ReplaceParameters: Enable parameter substitution in the file
        - TargetFileName: Output filename (uses `$safeprojectname`$ for project name)
    -->
    <Project File="$($projectFile.Name)" ReplaceParameters="true" TargetFileName="`$safeprojectname`$$projectExtension">

      <!-- ====================================================================
           PROJECT FILES
           Each ProjectItem is a file included in the project.
           - ReplaceParameters="true" enables substitution of template parameters
           - TargetFileName can use parameters like `$safeprojectname`$
           ==================================================================== -->
$allContentStr

    </Project>
  </TemplateContent>
</VSTemplate>
"@

# ---------------------------------------------------------------------------
# STEP 7: Write the vstemplate file
# ---------------------------------------------------------------------------

$outputPath = Join-Path $SourcePath "MyTemplate.vstemplate"

# Use UTF-8 encoding without BOM for best compatibility
$utf8NoBom = New-Object System.Text.UTF8Encoding($false)
[System.IO.File]::WriteAllText($outputPath, $vstemplate, $utf8NoBom)

Write-Verbose "Generated vstemplate: $outputPath"
Write-Output $outputPath
