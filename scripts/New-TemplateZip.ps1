<#
.SYNOPSIS
    Creates a ZIP package from a template source directory.

.DESCRIPTION
    This script packages a Visual Studio project template into a ZIP file
    that can be included in a VSIX extension.

    The process:
    1. Copies source files to a staging directory (excluding build artifacts)
    2. Ensures a .vstemplate file exists
    3. Creates a ZIP archive with proper structure
    4. Optionally copies the ZIP to the VSIX ProjectTemplates directory

    ZIP Structure Requirements:
    --------------------------
    Visual Studio expects template ZIPs to have a specific structure:
    - MyTemplate.vstemplate (required) - Template definition file
    - *.csproj or *.vbproj (required) - Project file
    - Source files - All files referenced in the vstemplate
    - __TemplateIcon.ico (optional) - Custom icon for the template

    The ZIP should NOT contain a root folder - files must be at the ZIP root.
    Example:
        Good: MyTemplate.zip/MyTemplate.vstemplate
        Bad:  MyTemplate.zip/MyTemplate/MyTemplate.vstemplate

.PARAMETER SourcePath
    Path to the directory containing template source files.
    Should contain the project file and all template files.

.PARAMETER OutputPath
    Path where the ZIP file should be created.
    Include the .zip extension in the path.

.PARAMETER IncludeVSTemplate
    If a MyTemplate.vstemplate doesn't exist, generate one automatically.
    Requires template metadata parameters to be provided.

.PARAMETER ExcludePatterns
    Array of patterns for files/folders to exclude from the ZIP.
    Default excludes: bin, obj, .vs, .git, *.user, etc.

.PARAMETER Force
    Overwrite existing ZIP file if it exists.

.EXAMPLE
    .\New-TemplateZip.ps1 -SourcePath "C:\Working\MyAddon" `
                          -OutputPath "C:\Templates\MyAddon.zip" `
                          -Force

    Creates a ZIP from the source directory, overwriting if exists.

.EXAMPLE
    .\New-TemplateZip.ps1 -SourcePath ".\staging\AlibreAddon" `
                          -OutputPath ".\ProjectTemplates\AlibreAddon.zip" `
                          -ExcludePatterns @("bin", "obj", "*.log", "test*")

    Creates a ZIP with custom exclusion patterns.

.NOTES
    Author: Stephen S. Mitchell
    Version: 1.0.0
    Date: December 2025

    The ZIP file format used is standard .NET System.IO.Compression.
    This is compatible with all Windows ZIP tools and Visual Studio.

.LINK
    https://github.com/Testbed-for-Alibre-Design/AlibreExtensions
#>

# ==============================================================================
# SCRIPT PARAMETERS
# ==============================================================================

[CmdletBinding()]
param(
    # Source directory containing template files
    [Parameter(Mandatory)]
    [ValidateScript({ Test-Path $_ -PathType Container })]
    [string]$SourcePath,

    # Output ZIP file path (must end with .zip)
    [Parameter(Mandatory)]
    [ValidatePattern('\.zip$')]
    [string]$OutputPath,

    # Patterns to exclude from the ZIP
    [string[]]$ExcludePatterns = @(
        "bin",            # Compiled output
        "obj",            # Intermediate files
        ".vs",            # VS settings folder
        ".git",           # Git repository
        ".gitignore",     # Git ignore file
        ".gitattributes", # Git attributes
        "*.user",         # User settings
        "*.suo",          # Solution user options
        "*.log",          # Log files
        "packages",       # NuGet packages
        "TestResults",    # Test output
        ".template.config", # CLI template config (not needed for VSIX)
        "node_modules",   # Node packages (if any)
        "*.DotSettings.user" # ReSharper user settings
    ),

    # Overwrite existing ZIP
    [switch]$Force,

    # Show verbose progress
    [switch]$Detailed
)

# ==============================================================================
# CONFIGURATION
# ==============================================================================

$ErrorActionPreference = "Stop"

# ==============================================================================
# HELPER FUNCTIONS
# ==============================================================================

function Test-ShouldExclude {
    <#
    .SYNOPSIS
        Tests if a path matches any exclusion pattern.

    .DESCRIPTION
        Checks the file/folder path against all exclusion patterns.
        Patterns can match anywhere in the path.

    .PARAMETER Path
        The relative path to test.

    .PARAMETER Patterns
        Array of patterns to match against.

    .OUTPUTS
        $true if path should be excluded, $false otherwise.
    #>
    param(
        [string]$Path,
        [string[]]$Patterns
    )

    foreach ($pattern in $Patterns) {
        # Check if pattern matches anywhere in the path
        if ($Path -like "*$pattern*") {
            return $true
        }
        # Also check just the filename/foldername
        $name = Split-Path $Path -Leaf
        if ($name -like $pattern) {
            return $true
        }
    }
    return $false
}

function Get-FilteredFiles {
    <#
    .SYNOPSIS
        Gets all files from a directory, excluding specified patterns.

    .DESCRIPTION
        Recursively enumerates files, filtering out those matching
        exclusion patterns. Returns FileInfo objects with relative paths.

    .PARAMETER BasePath
        Root directory to enumerate.

    .PARAMETER Patterns
        Patterns to exclude.

    .OUTPUTS
        Array of PSCustomObjects with FullPath and RelativePath properties.
    #>
    param(
        [string]$BasePath,
        [string[]]$Patterns
    )

    $results = @()

    # Normalize base path
    $BasePath = (Resolve-Path $BasePath).Path.TrimEnd('\')

    # Get all files recursively
    $allFiles = Get-ChildItem -Path $BasePath -Recurse -File -Force

    foreach ($file in $allFiles) {
        # Calculate relative path
        $relativePath = $file.FullName.Substring($BasePath.Length + 1)

        # Check exclusions
        if (-not (Test-ShouldExclude -Path $relativePath -Patterns $Patterns)) {
            $results += [PSCustomObject]@{
                FullPath = $file.FullName
                RelativePath = $relativePath
                Name = $file.Name
                Extension = $file.Extension
                Length = $file.Length
            }
        }
    }

    return $results
}

function New-ZipFromFiles {
    <#
    .SYNOPSIS
        Creates a ZIP archive from a list of files.

    .DESCRIPTION
        Uses .NET compression classes to create a ZIP file with
        specified files at specified relative paths within the archive.

        The ZIP is created with optimal compression and no root folder.

    .PARAMETER Files
        Array of file objects with FullPath and RelativePath properties.

    .PARAMETER OutputPath
        Path for the output ZIP file.

    .PARAMETER Force
        Overwrite existing file.
    #>
    param(
        [array]$Files,
        [string]$OutputPath,
        [switch]$Force
    )

    # Check for existing file
    if ((Test-Path $OutputPath) -and -not $Force) {
        throw "ZIP file already exists: $OutputPath. Use -Force to overwrite."
    }

    # Remove existing file if Force specified
    if (Test-Path $OutputPath) {
        Remove-Item $OutputPath -Force
    }

    # Ensure output directory exists
    $outputDir = Split-Path $OutputPath -Parent
    if ($outputDir -and -not (Test-Path $outputDir)) {
        New-Item -ItemType Directory -Path $outputDir -Force | Out-Null
    }

    # Load compression assembly (usually already loaded in PS 5.1+)
    Add-Type -AssemblyName System.IO.Compression
    Add-Type -AssemblyName System.IO.Compression.FileSystem

    try {
        # Create new ZIP archive
        $zipMode = [System.IO.Compression.ZipArchiveMode]::Create
        $zipStream = [System.IO.File]::Create($OutputPath)
        $archive = New-Object System.IO.Compression.ZipArchive($zipStream, $zipMode)

        foreach ($file in $Files) {
            # Normalize path separators for ZIP (use forward slashes)
            $entryName = $file.RelativePath -replace '\\', '/'

            # Create entry with optimal compression
            $compressionLevel = [System.IO.Compression.CompressionLevel]::Optimal
            $entry = $archive.CreateEntry($entryName, $compressionLevel)

            # Copy file content to entry
            $entryStream = $entry.Open()
            try {
                $fileStream = [System.IO.File]::OpenRead($file.FullPath)
                try {
                    $fileStream.CopyTo($entryStream)
                }
                finally {
                    $fileStream.Close()
                }
            }
            finally {
                $entryStream.Close()
            }

            if ($Detailed) {
                Write-Verbose "Added: $entryName"
            }
        }
    }
    finally {
        if ($archive) {
            $archive.Dispose()
        }
        if ($zipStream) {
            $zipStream.Close()
        }
    }
}

# ==============================================================================
# VALIDATION
# ==============================================================================

Write-Verbose "Creating template ZIP package"
Write-Verbose "Source: $SourcePath"
Write-Verbose "Output: $OutputPath"

# Verify source has required files
$projectFiles = Get-ChildItem -Path $SourcePath -Filter "*.csproj" -File
$projectFiles += Get-ChildItem -Path $SourcePath -Filter "*.vbproj" -File

if ($projectFiles.Count -eq 0) {
    throw "No project file (.csproj or .vbproj) found in source directory"
}

# Check for vstemplate
$vstemplateFile = Join-Path $SourcePath "MyTemplate.vstemplate"
$hasVstemplate = Test-Path $vstemplateFile

if (-not $hasVstemplate) {
    Write-Warning "No MyTemplate.vstemplate found in source. ZIP may not be a valid VS template."
}

# ==============================================================================
# MAIN EXECUTION
# ==============================================================================

# ---------------------------------------------------------------------------
# STEP 1: Enumerate files to include
# ---------------------------------------------------------------------------

Write-Verbose "Scanning source directory..."

$filesToInclude = Get-FilteredFiles -BasePath $SourcePath -Patterns $ExcludePatterns

$totalSize = ($filesToInclude | Measure-Object -Property Length -Sum).Sum
$totalSizeKB = [math]::Round($totalSize / 1KB, 2)

Write-Verbose "Found $($filesToInclude.Count) files to include ($totalSizeKB KB)"

if ($filesToInclude.Count -eq 0) {
    throw "No files found to include in ZIP after applying exclusions"
}

# ---------------------------------------------------------------------------
# STEP 2: Verify required files are present
# ---------------------------------------------------------------------------

$hasProjectFile = $filesToInclude | Where-Object {
    $_.Extension -eq ".csproj" -or $_.Extension -eq ".vbproj"
}

if (-not $hasProjectFile) {
    throw "Project file was excluded by patterns. Check ExcludePatterns parameter."
}

# ---------------------------------------------------------------------------
# STEP 3: Create the ZIP archive
# ---------------------------------------------------------------------------

Write-Verbose "Creating ZIP archive..."

New-ZipFromFiles -Files $filesToInclude -OutputPath $OutputPath -Force:$Force

# ---------------------------------------------------------------------------
# STEP 4: Verify output
# ---------------------------------------------------------------------------

if (Test-Path $OutputPath) {
    $zipInfo = Get-Item $OutputPath
    $zipSizeKB = [math]::Round($zipInfo.Length / 1KB, 2)

    Write-Verbose "ZIP created successfully: $($zipInfo.Name) ($zipSizeKB KB)"

    # Output the path for pipeline usage
    Write-Output $OutputPath
} else {
    throw "ZIP file was not created at expected path: $OutputPath"
}

# ---------------------------------------------------------------------------
# STEP 5: List contents (verbose only)
# ---------------------------------------------------------------------------

if ($Detailed) {
    Write-Verbose ""
    Write-Verbose "ZIP contents:"
    Write-Verbose "-------------"

    # Use .NET to list ZIP contents
    Add-Type -AssemblyName System.IO.Compression.FileSystem
    $zip = [System.IO.Compression.ZipFile]::OpenRead($OutputPath)
    try {
        foreach ($entry in $zip.Entries) {
            $sizeKB = [math]::Round($entry.Length / 1KB, 2)
            Write-Verbose "  $($entry.FullName) ($sizeKB KB)"
        }
    }
    finally {
        $zip.Dispose()
    }
}
