<#
.SYNOPSIS
    Interactive menu for Alibre Design Extensions build system.

.DESCRIPTION
    This script provides a user-friendly interactive menu to access all build,
    test, and deployment scripts in the Alibre Extensions project.

    FEATURES:
    - Color-coded menu categories
    - Guided workflow options
    - Parameter prompts for complex scripts
    - Status indicators for prerequisites
    - Quick access to common tasks

.EXAMPLE
    .\Menu.ps1

    Launches the interactive menu.

.EXAMPLE
    .\Menu.ps1 -QuickBuild

    Runs a full build without showing the menu.

.NOTES
    Author: Stephen S. Mitchell
    Version: 1.0.0
#>

[CmdletBinding()]
param(
    [switch]$QuickBuild,
    [switch]$QuickRelease
)

$ErrorActionPreference = "Stop"
$Host.UI.RawUI.WindowTitle = "Alibre Extensions - Build Menu"

# ==============================================================================
# CONFIGURATION
# ==============================================================================

$script:RootDir = $PSScriptRoot
if (-not $script:RootDir) {
    $script:RootDir = Split-Path -Parent $MyInvocation.MyCommand.Path
}

# Load build config
$script:ConfigPath = Join-Path $script:RootDir "build.config.json"
$script:Config = $null
if (Test-Path $script:ConfigPath) {
    try {
        $script:Config = Get-Content $script:ConfigPath -Raw | ConvertFrom-Json
    } catch { }
}

function Get-ConfigValue {
    param([string]$Path, $Default = $null)
    if (-not $script:Config) { return $Default }
    $parts = $Path -split '\.'
    $value = $script:Config
    foreach ($part in $parts) {
        if ($null -eq $value) { return $Default }
        $value = $value.$part
    }
    if ($null -eq $value) { return $Default }
    return $value
}

$script:Version = "$(Get-ConfigValue 'version.major' 1).$(Get-ConfigValue 'version.minor' 0).$(Get-ConfigValue 'version.patch' 0)"
$script:ProductName = Get-ConfigValue "product.name" "Alibre Design"

# ==============================================================================
# CONSOLE HELPERS
# ==============================================================================

function Clear-MenuScreen {
    Clear-Host
}

function Write-MenuHeader {
    $header = @"

================================================================================
     _    _ _ _               _____      _                 _
    / \  | (_) |__  _ __ ___ | ____|_  _| |_ ___ _ __  ___(_) ___  _ __  ___
   / _ \ | | | '_ \| '__/ _ \|  _| \ \/ / __/ _ \ '_ \/ __| |/ _ \| '_ \/ __|
  / ___ \| | | |_) | | |  __/| |___ >  <| ||  __/ | | \__ \ | (_) | | | \__ \
 /_/   \_\_|_|_.__/|_|  \___||_____/_/\_\\__\___|_| |_|___/_|\___/|_| |_|___/

                    BUILD SYSTEM v$script:Version
================================================================================

"@
    Write-Host $header -ForegroundColor Cyan
}

function Write-MenuSection {
    param([string]$Title, [string]$Color = "Yellow")
    Write-Host ""
    Write-Host "  $Title" -ForegroundColor $Color
    Write-Host "  $("-" * ($Title.Length))" -ForegroundColor DarkGray
}

function Write-MenuItem {
    param(
        [string]$Key,
        [string]$Label,
        [string]$Description = "",
        [string]$Status = "",
        [switch]$Disabled
    )

    $keyColor = if ($Disabled) { "DarkGray" } else { "Green" }
    $labelColor = if ($Disabled) { "DarkGray" } else { "White" }
    $descColor = "DarkGray"

    $keyPart = "  [$Key]"
    $labelPart = " $Label"

    Write-Host $keyPart -ForegroundColor $keyColor -NoNewline
    Write-Host $labelPart -ForegroundColor $labelColor -NoNewline

    if ($Description) {
        Write-Host " - $Description" -ForegroundColor $descColor -NoNewline
    }

    if ($Status) {
        $statusColor = switch -Regex ($Status) {
            "OK|Ready|Installed" { "Green" }
            "Missing|Not Found" { "Red" }
            "Warning" { "Yellow" }
            default { "DarkGray" }
        }
        Write-Host " [$Status]" -ForegroundColor $statusColor -NoNewline
    }

    Write-Host ""
}

function Write-MenuFooter {
    Write-Host ""
    Write-Host "  $("=" * 74)" -ForegroundColor DarkGray
    Write-Host "  [Q] Quit   [H] Help   [S] Status   [C] Clear Screen" -ForegroundColor DarkGray
    Write-Host ""
}

function Read-MenuChoice {
    param([string]$Prompt = "Select option")
    Write-Host ""
    Write-Host "  $Prompt" -ForegroundColor Cyan -NoNewline
    Write-Host ": " -NoNewline
    $choice = Read-Host
    return $choice.Trim().ToUpper()
}

function Pause-Menu {
    param([string]$Message = "Press any key to continue...")
    Write-Host ""
    Write-Host "  $Message" -ForegroundColor DarkGray
    $null = $Host.UI.RawUI.ReadKey("NoEcho,IncludeKeyDown")
}

function Confirm-Action {
    param([string]$Message)
    Write-Host ""
    Write-Host "  $Message (Y/N)? " -ForegroundColor Yellow -NoNewline
    $response = Read-Host
    return $response.Trim().ToUpper() -eq "Y"
}

# ==============================================================================
# STATUS CHECKS
# ==============================================================================

function Get-Prerequisites {
    $prereqs = @{}

    # GitHub CLI
    $gh = Get-Command "gh" -ErrorAction SilentlyContinue
    $prereqs["GitHubCLI"] = @{
        Name = "GitHub CLI (gh)"
        Installed = ($null -ne $gh)
        Path = if ($gh) { $gh.Path } else { $null }
        InstallCmd = "winget install GitHub.cli"
    }

    # Inno Setup
    $innoPath = @(
        "C:\Program Files (x86)\Inno Setup 6\ISCC.exe",
        "C:\Program Files\Inno Setup 6\ISCC.exe"
    ) | Where-Object { Test-Path $_ } | Select-Object -First 1
    $prereqs["InnoSetup"] = @{
        Name = "Inno Setup 6"
        Installed = ($null -ne $innoPath)
        Path = $innoPath
        InstallCmd = "Download from https://jrsoftware.org/isdl.php"
    }

    # MSBuild
    $msbuildPaths = @(
        "C:\Program Files\Microsoft Visual Studio\2022\Enterprise\MSBuild\Current\Bin\MSBuild.exe",
        "C:\Program Files\Microsoft Visual Studio\2022\Professional\MSBuild\Current\Bin\MSBuild.exe",
        "C:\Program Files\Microsoft Visual Studio\2022\Community\MSBuild\Current\Bin\MSBuild.exe"
    )
    $msbuild = $msbuildPaths | Where-Object { Test-Path $_ } | Select-Object -First 1
    $prereqs["MSBuild"] = @{
        Name = "MSBuild (Visual Studio)"
        Installed = ($null -ne $msbuild)
        Path = $msbuild
        InstallCmd = "Install Visual Studio 2022"
    }

    # NuGet
    $nuget = Get-Command "nuget" -ErrorAction SilentlyContinue
    $prereqs["NuGet"] = @{
        Name = "NuGet CLI"
        Installed = ($null -ne $nuget)
        Path = if ($nuget) { $nuget.Path } else { $null }
        InstallCmd = "Auto-downloaded during build"
    }

    # Git
    $git = Get-Command "git" -ErrorAction SilentlyContinue
    $prereqs["Git"] = @{
        Name = "Git"
        Installed = ($null -ne $git)
        Path = if ($git) { $git.Path } else { $null }
        InstallCmd = "winget install Git.Git"
    }

    return $prereqs
}

function Show-StatusScreen {
    Clear-MenuScreen
    Write-MenuHeader

    Write-Host "  SYSTEM STATUS" -ForegroundColor Yellow
    Write-Host "  $("=" * 74)" -ForegroundColor DarkGray
    Write-Host ""

    # Prerequisites
    Write-Host "  Prerequisites:" -ForegroundColor White
    $prereqs = Get-Prerequisites
    foreach ($key in $prereqs.Keys | Sort-Object) {
        $p = $prereqs[$key]
        $status = if ($p.Installed) { "[OK]" } else { "[MISSING]" }
        $color = if ($p.Installed) { "Green" } else { "Red" }
        Write-Host "    $($p.Name.PadRight(25)) " -NoNewline
        Write-Host $status -ForegroundColor $color
        if (-not $p.Installed) {
            Write-Host "      Install: $($p.InstallCmd)" -ForegroundColor DarkGray
        }
    }

    Write-Host ""

    # Build Outputs
    Write-Host "  Build Outputs:" -ForegroundColor White

    $vsixPath = Join-Path $script:RootDir "bin"
    $vsix = Get-ChildItem -Path $vsixPath -Filter "*.vsix" -ErrorAction SilentlyContinue |
            Sort-Object LastWriteTime -Descending | Select-Object -First 1
    if ($vsix) {
        Write-Host "    VSIX:       $($vsix.Name)" -ForegroundColor Green
        Write-Host "                $(Get-Date $vsix.LastWriteTime -Format 'yyyy-MM-dd HH:mm')" -ForegroundColor DarkGray
    } else {
        Write-Host "    VSIX:       [Not Built]" -ForegroundColor Yellow
    }

    $nupkg = Get-ChildItem -Path $vsixPath -Filter "*.nupkg" -ErrorAction SilentlyContinue |
             Sort-Object LastWriteTime -Descending | Select-Object -First 1
    if ($nupkg) {
        Write-Host "    NuGet:      $($nupkg.Name)" -ForegroundColor Green
    } else {
        Write-Host "    NuGet:      [Not Built]" -ForegroundColor Yellow
    }

    $installersPath = Join-Path $script:RootDir "Installers"
    $installers = Get-ChildItem -Path $installersPath -Filter "*.exe" -ErrorAction SilentlyContinue
    Write-Host "    Installers: $($installers.Count) built" -ForegroundColor $(if ($installers.Count -gt 0) { "Green" } else { "Yellow" })

    Write-Host ""

    # Project Stats
    Write-Host "  Project Statistics:" -ForegroundColor White
    $projectsPath = Join-Path $script:RootDir "Working\Projects"
    $projects = Get-ChildItem -Path $projectsPath -Directory -ErrorAction SilentlyContinue |
                Where-Object { $_.Name -notmatch "^(bin|obj|\.vs|nul|Solution)$" }
    Write-Host "    Projects:   $($projects.Count)" -ForegroundColor Cyan

    $templateZips = Get-ChildItem -Path (Join-Path $script:RootDir "Extension\VSExtensionForAlibreDesign\ProjectTemplates") -Filter "*.zip" -ErrorAction SilentlyContinue
    Write-Host "    Templates:  $($templateZips.Count)" -ForegroundColor Cyan

    Write-Host ""
    Pause-Menu
}

# ==============================================================================
# SCRIPT RUNNERS
# ==============================================================================

function Invoke-Script {
    param(
        [string]$ScriptPath,
        [hashtable]$Parameters = @{},
        [switch]$WaitForKey
    )

    if (-not (Test-Path $ScriptPath)) {
        Write-Host "  Script not found: $ScriptPath" -ForegroundColor Red
        Pause-Menu
        return
    }

    Write-Host ""
    Write-Host "  Running: $(Split-Path $ScriptPath -Leaf)" -ForegroundColor Cyan
    Write-Host "  $("=" * 74)" -ForegroundColor DarkGray
    Write-Host ""

    try {
        & $ScriptPath @Parameters
    }
    catch {
        Write-Host ""
        Write-Host "  ERROR: $_" -ForegroundColor Red
    }

    if ($WaitForKey) {
        Pause-Menu
    }
}

function Invoke-Cmd {
    param(
        [string]$CmdPath,
        [switch]$WaitForKey
    )

    if (-not (Test-Path $CmdPath)) {
        Write-Host "  Script not found: $CmdPath" -ForegroundColor Red
        Pause-Menu
        return
    }

    Write-Host ""
    Write-Host "  Running: $(Split-Path $CmdPath -Leaf)" -ForegroundColor Cyan
    Write-Host "  $("=" * 74)" -ForegroundColor DarkGray
    Write-Host ""

    Push-Location $script:RootDir
    try {
        & cmd /c $CmdPath
    }
    finally {
        Pop-Location
    }

    if ($WaitForKey) {
        Pause-Menu
    }
}

# ==============================================================================
# MENU SCREENS
# ==============================================================================

function Show-MainMenu {
    Clear-MenuScreen
    Write-MenuHeader

    Write-MenuSection "QUICK START" "Green"
    Write-MenuItem -Key "1" -Label "Full Build + Installers" -Description "Complete build pipeline"
    Write-MenuItem -Key "2" -Label "Build Templates Only" -Description "VSIX + NuGet packages"
    Write-MenuItem -Key "3" -Label "Build Installers Only" -Description "Inno Setup .exe files"

    Write-MenuSection "BUILD OPTIONS" "Yellow"
    Write-MenuItem -Key "B" -Label "Build Menu" -Description "All build options"
    Write-MenuItem -Key "T" -Label "Test Menu" -Description "Run tests and validations"
    Write-MenuItem -Key "R" -Label "Release Menu" -Description "Publish to GitHub"
    Write-MenuItem -Key "I" -Label "Install Menu" -Description "Install/deploy extensions"

    Write-MenuSection "UTILITIES" "Cyan"
    Write-MenuItem -Key "P" -Label "Project List" -Description "View all projects"
    Write-MenuItem -Key "A" -Label "Audit Reports" -Description "Generate documentation"
    Write-MenuItem -Key "O" -Label "Open Folder" -Description "Open in Explorer"

    Write-MenuFooter

    return Read-MenuChoice
}

function Show-BuildMenu {
    Clear-MenuScreen
    Write-MenuHeader

    Write-Host "  BUILD OPTIONS" -ForegroundColor Yellow
    Write-Host "  $("=" * 74)" -ForegroundColor DarkGray
    Write-Host ""

    Write-MenuSection "COMPLETE BUILDS" "Green"
    Write-MenuItem -Key "1" -Label "build-full-with-installers.cmd" -Description "Full pipeline (VSIX + NuGet + Installers)"
    Write-MenuItem -Key "2" -Label "build-full.cmd" -Description "VSIX + NuGet (no installers)"
    Write-MenuItem -Key "3" -Label "build.cmd" -Description "Quick VSIX build"

    Write-MenuSection "POWERSHELL SCRIPTS" "Yellow"
    Write-MenuItem -Key "4" -Label "Build-All.ps1" -Description "Template discovery + VSIX + NuGet"
    Write-MenuItem -Key "5" -Label "Build-Installers.ps1" -Description "Build Inno Setup installers"
    Write-MenuItem -Key "6" -Label "Build-Installers.ps1 -Clean" -Description "Clean rebuild of installers"

    Write-MenuSection "TEMPLATE SCRIPTS" "Cyan"
    Write-MenuItem -Key "7" -Label "Scripts\Build-Templates.ps1" -Description "Build template ZIPs"
    Write-MenuItem -Key "8" -Label "Scripts\Build-DotnetTemplates.ps1" -Description "Build .NET CLI templates"

    Write-MenuSection "OPTIONS"
    Write-MenuItem -Key "F" -Label "Filter by Project" -Description "Build specific project only"
    Write-MenuItem -Key "D" -Label "Debug Configuration" -Description "Build in Debug mode"

    Write-Host ""
    Write-MenuItem -Key "M" -Label "Back to Main Menu"
    Write-MenuFooter

    return Read-MenuChoice
}

function Show-TestMenu {
    Clear-MenuScreen
    Write-MenuHeader

    Write-Host "  TEST & VALIDATION" -ForegroundColor Yellow
    Write-Host "  $("=" * 74)" -ForegroundColor DarkGray
    Write-Host ""

    Write-MenuSection "PRE-BUILD TESTS" "Green"
    Write-MenuItem -Key "1" -Label "Test-PreBuild.ps1" -Description "Validate before building"
    Write-MenuItem -Key "2" -Label "test-pre.cmd" -Description "Pre-build checks (CMD)"

    Write-MenuSection "POST-BUILD TESTS" "Yellow"
    Write-MenuItem -Key "3" -Label "Test-Templates.ps1" -Description "Validate template packages"
    Write-MenuItem -Key "4" -Label "test-post.cmd" -Description "Post-build validation (CMD)"
    Write-MenuItem -Key "5" -Label "test.cmd" -Description "Full test suite"

    Write-MenuSection "SPECIFIC TESTS" "Cyan"
    Write-MenuItem -Key "6" -Label "Test-AddonRegistry.ps1" -Description "Check addon registry"
    Write-MenuItem -Key "7" -Label "Scripts\Test-CliTemplates.ps1" -Description "Test CLI template installation"

    Write-Host ""
    Write-MenuItem -Key "M" -Label "Back to Main Menu"
    Write-MenuFooter

    return Read-MenuChoice
}

function Show-ReleaseMenu {
    Clear-MenuScreen
    Write-MenuHeader

    Write-Host "  RELEASE & PUBLISH" -ForegroundColor Yellow
    Write-Host "  $("=" * 74)" -ForegroundColor DarkGray
    Write-Host ""

    # Check GitHub CLI
    $gh = Get-Command "gh" -ErrorAction SilentlyContinue
    $ghStatus = if ($gh) { "Ready" } else { "Not Installed" }

    Write-MenuSection "GITHUB RELEASES" "Green"
    Write-MenuItem -Key "1" -Label "List Projects" -Description "Show all projects and installers" -Status $ghStatus
    Write-MenuItem -Key "2" -Label "Publish All" -Description "Release all built installers" -Status $ghStatus
    Write-MenuItem -Key "3" -Label "Publish Single Project" -Description "Select project to release" -Status $ghStatus
    Write-MenuItem -Key "4" -Label "Build + Publish All" -Description "Full build then release" -Status $ghStatus

    Write-MenuSection "OPTIONS" "Yellow"
    Write-MenuItem -Key "D" -Label "Draft Release" -Description "Create as draft (review before publish)"
    Write-MenuItem -Key "P" -Label "Prerelease" -Description "Mark as prerelease"
    Write-MenuItem -Key "F" -Label "Force Overwrite" -Description "Replace existing releases"

    Write-MenuSection "PREREQUISITES" "Cyan"
    Write-MenuItem -Key "G" -Label "Install GitHub CLI" -Description "winget install GitHub.cli"
    Write-MenuItem -Key "L" -Label "Login to GitHub" -Description "gh auth login"

    Write-Host ""
    Write-MenuItem -Key "M" -Label "Back to Main Menu"
    Write-MenuFooter

    return Read-MenuChoice
}

function Show-InstallMenu {
    Clear-MenuScreen
    Write-MenuHeader

    Write-Host "  INSTALL & DEPLOY" -ForegroundColor Yellow
    Write-Host "  $("=" * 74)" -ForegroundColor DarkGray
    Write-Host ""

    Write-MenuSection "VSIX EXTENSION" "Green"
    Write-MenuItem -Key "1" -Label "Install VSIX (Normal)" -Description "Install to Visual Studio"
    Write-MenuItem -Key "2" -Label "Install VSIX (Experimental)" -Description "Install to VS Experimental instance"
    Write-MenuItem -Key "3" -Label "Uninstall VSIX" -Description "Remove extension from VS"
    Write-MenuItem -Key "4" -Label "Launch VS Experimental" -Description "Open VS experimental instance"

    Write-MenuSection "CLI TEMPLATES" "Yellow"
    Write-MenuItem -Key "5" -Label "Install NuGet Package" -Description "Install dotnet templates locally"
    Write-MenuItem -Key "6" -Label "Uninstall NuGet Package" -Description "Remove dotnet templates"
    Write-MenuItem -Key "7" -Label "List Installed Templates" -Description "Show installed dotnet templates"

    Write-MenuSection "ADDON INSTALLERS" "Cyan"
    Write-MenuItem -Key "8" -Label "Run Installer" -Description "Execute a built installer"
    Write-MenuItem -Key "9" -Label "Open Installers Folder" -Description "Browse installer files"

    Write-Host ""
    Write-MenuItem -Key "M" -Label "Back to Main Menu"
    Write-MenuFooter

    return Read-MenuChoice
}

function Show-ProjectList {
    Clear-MenuScreen
    Write-MenuHeader

    Write-Host "  PROJECT INVENTORY" -ForegroundColor Yellow
    Write-Host "  $("=" * 74)" -ForegroundColor DarkGray
    Write-Host ""

    $projectsPath = Join-Path $script:RootDir "Working\Projects"
    $installersPath = Join-Path $script:RootDir "Installers"

    $projects = Get-ChildItem -Path $projectsPath -Directory -ErrorAction SilentlyContinue |
                Where-Object { $_.Name -notmatch "^(bin|obj|\.vs|nul|Solution)$" } |
                Sort-Object Name

    Write-Host ("  {0,-40} {1,-15} {2}" -f "PROJECT", "TYPE", "INSTALLER") -ForegroundColor White
    Write-Host "  $("-" * 74)" -ForegroundColor DarkGray

    foreach ($proj in $projects) {
        # Check for project file type
        $csproj = Get-ChildItem -Path $proj.FullName -Filter "*.csproj" -Recurse -ErrorAction SilentlyContinue | Select-Object -First 1
        $vbproj = Get-ChildItem -Path $proj.FullName -Filter "*.vbproj" -Recurse -ErrorAction SilentlyContinue | Select-Object -First 1
        $fsproj = Get-ChildItem -Path $proj.FullName -Filter "*.fsproj" -Recurse -ErrorAction SilentlyContinue | Select-Object -First 1

        $type = if ($csproj) { "C#" } elseif ($vbproj) { "VB.NET" } elseif ($fsproj) { "F#" } else { "-" }

        # Check for installer
        $installer = Get-ChildItem -Path $installersPath -Filter "*$($proj.Name)*-Setup.exe" -ErrorAction SilentlyContinue | Select-Object -First 1
        $hasInstaller = if ($installer) { "Yes" } else { "-" }
        $color = if ($installer) { "Green" } else { "Gray" }

        Write-Host ("  {0,-40} {1,-15} {2}" -f $proj.Name, $type, $hasInstaller) -ForegroundColor $color
    }

    Write-Host ""
    Write-Host "  Total: $($projects.Count) projects" -ForegroundColor Cyan
    Write-Host ""

    Pause-Menu
}

function Show-Help {
    Clear-MenuScreen
    Write-MenuHeader

    Write-Host "  HELP & DOCUMENTATION" -ForegroundColor Yellow
    Write-Host "  $("=" * 74)" -ForegroundColor DarkGray
    Write-Host ""

    Write-Host "  QUICK START:" -ForegroundColor White
    Write-Host "    1. Run option [1] to build everything (VSIX + NuGet + Installers)" -ForegroundColor Gray
    Write-Host "    2. Use [I] Install Menu to deploy the VSIX to Visual Studio" -ForegroundColor Gray
    Write-Host "    3. Use [R] Release Menu to publish installers to GitHub" -ForegroundColor Gray
    Write-Host ""

    Write-Host "  BUILD OUTPUTS:" -ForegroundColor White
    Write-Host "    bin\*.vsix        - Visual Studio extension package" -ForegroundColor Gray
    Write-Host "    bin\*.nupkg       - .NET CLI template package" -ForegroundColor Gray
    Write-Host "    Installers\*.exe  - Inno Setup installers for addons" -ForegroundColor Gray
    Write-Host ""

    Write-Host "  KEY SCRIPTS:" -ForegroundColor White
    Write-Host "    Build-All.ps1         - Main build script (templates + VSIX + NuGet)" -ForegroundColor Gray
    Write-Host "    Build-Installers.ps1  - Builds Inno Setup installers" -ForegroundColor Gray
    Write-Host "    Publish-Release.ps1   - Publishes to GitHub releases" -ForegroundColor Gray
    Write-Host ""

    Write-Host "  CONFIGURATION:" -ForegroundColor White
    Write-Host "    build.config.json     - Central configuration file" -ForegroundColor Gray
    Write-Host "    release.config.json   - Per-project release config (in project folder)" -ForegroundColor Gray
    Write-Host ""

    Write-Host "  PREREQUISITES:" -ForegroundColor White
    Write-Host "    Visual Studio 2022    - For building VSIX" -ForegroundColor Gray
    Write-Host "    Inno Setup 6          - For building installers" -ForegroundColor Gray
    Write-Host "    GitHub CLI (gh)       - For publishing releases" -ForegroundColor Gray
    Write-Host ""

    Write-Host "  DOCUMENTATION:" -ForegroundColor White
    Write-Host "    Docs\                 - Project documentation" -ForegroundColor Gray
    Write-Host "    Docs\_audit\          - Build audit reports" -ForegroundColor Gray
    Write-Host "    Docs\_logs\           - Build logs" -ForegroundColor Gray
    Write-Host ""

    Pause-Menu
}

# ==============================================================================
# MENU HANDLERS
# ==============================================================================

function Handle-BuildMenu {
    while ($true) {
        $choice = Show-BuildMenu

        switch ($choice) {
            "1" { Invoke-Cmd (Join-Path $script:RootDir "build-full-with-installers.cmd") -WaitForKey }
            "2" { Invoke-Cmd (Join-Path $script:RootDir "build-full.cmd") -WaitForKey }
            "3" { Invoke-Cmd (Join-Path $script:RootDir "build.cmd") -WaitForKey }
            "4" { Invoke-Script (Join-Path $script:RootDir "Build-All.ps1") -WaitForKey }
            "5" { Invoke-Script (Join-Path $script:RootDir "Build-Installers.ps1") -WaitForKey }
            "6" { Invoke-Script (Join-Path $script:RootDir "Build-Installers.ps1") -Parameters @{ Clean = $true } -WaitForKey }
            "7" { Invoke-Script (Join-Path $script:RootDir "Scripts\Build-Templates.ps1") -WaitForKey }
            "8" { Invoke-Script (Join-Path $script:RootDir "Scripts\Build-DotnetTemplates.ps1") -WaitForKey }
            "F" {
                Write-Host ""
                Write-Host "  Enter project name filter (e.g., alibre-export*): " -ForegroundColor Cyan -NoNewline
                $filter = Read-Host
                if ($filter) {
                    Invoke-Script (Join-Path $script:RootDir "Build-Installers.ps1") -Parameters @{ ProjectFilter = $filter } -WaitForKey
                }
            }
            "D" {
                Invoke-Script (Join-Path $script:RootDir "Build-All.ps1") -Parameters @{ Configuration = "Debug" } -WaitForKey
            }
            "M" { return }
            "Q" { exit 0 }
            "H" { Show-Help }
            "S" { Show-StatusScreen }
            "C" { }
            default { }
        }
    }
}

function Handle-TestMenu {
    while ($true) {
        $choice = Show-TestMenu

        switch ($choice) {
            "1" { Invoke-Script (Join-Path $script:RootDir "Test-PreBuild.ps1") -WaitForKey }
            "2" { Invoke-Cmd (Join-Path $script:RootDir "test-pre.cmd") -WaitForKey }
            "3" { Invoke-Script (Join-Path $script:RootDir "Test-Templates.ps1") -WaitForKey }
            "4" { Invoke-Cmd (Join-Path $script:RootDir "test-post.cmd") -WaitForKey }
            "5" { Invoke-Cmd (Join-Path $script:RootDir "test.cmd") -WaitForKey }
            "6" { Invoke-Script (Join-Path $script:RootDir "Test-AddonRegistry.ps1") -WaitForKey }
            "7" { Invoke-Script (Join-Path $script:RootDir "Scripts\Test-CliTemplates.ps1") -WaitForKey }
            "M" { return }
            "Q" { exit 0 }
            "H" { Show-Help }
            "S" { Show-StatusScreen }
            "C" { }
            default { }
        }
    }
}

function Handle-ReleaseMenu {
    while ($true) {
        $choice = Show-ReleaseMenu

        switch ($choice) {
            "1" { Invoke-Script (Join-Path $script:RootDir "Publish-Release.ps1") -Parameters @{ ListProjects = $true } -WaitForKey }
            "2" {
                if (Confirm-Action "Publish all installers to GitHub") {
                    Invoke-Script (Join-Path $script:RootDir "Publish-Release.ps1") -WaitForKey
                }
            }
            "3" {
                Write-Host ""
                Write-Host "  Enter project name: " -ForegroundColor Cyan -NoNewline
                $proj = Read-Host
                if ($proj) {
                    Invoke-Script (Join-Path $script:RootDir "Publish-Release.ps1") -Parameters @{ Project = $proj } -WaitForKey
                }
            }
            "4" {
                if (Confirm-Action "Build all installers then publish to GitHub") {
                    Invoke-Script (Join-Path $script:RootDir "Publish-Release.ps1") -Parameters @{ BuildFirst = $true } -WaitForKey
                }
            }
            "D" {
                Write-Host ""
                Write-Host "  Enter project name (or * for all): " -ForegroundColor Cyan -NoNewline
                $proj = Read-Host
                $params = @{ Draft = $true }
                if ($proj -and $proj -ne "*") { $params["Project"] = $proj }
                Invoke-Script (Join-Path $script:RootDir "Publish-Release.ps1") -Parameters $params -WaitForKey
            }
            "P" {
                Write-Host ""
                Write-Host "  Enter project name (or * for all): " -ForegroundColor Cyan -NoNewline
                $proj = Read-Host
                $params = @{ Prerelease = $true }
                if ($proj -and $proj -ne "*") { $params["Project"] = $proj }
                Invoke-Script (Join-Path $script:RootDir "Publish-Release.ps1") -Parameters $params -WaitForKey
            }
            "F" {
                Write-Host ""
                Write-Host "  Enter project name (or * for all): " -ForegroundColor Cyan -NoNewline
                $proj = Read-Host
                $params = @{ Force = $true }
                if ($proj -and $proj -ne "*") { $params["Project"] = $proj }
                Invoke-Script (Join-Path $script:RootDir "Publish-Release.ps1") -Parameters $params -WaitForKey
            }
            "G" {
                Write-Host ""
                Write-Host "  Run: winget install GitHub.cli" -ForegroundColor Cyan
                Pause-Menu
            }
            "L" {
                Write-Host ""
                & gh auth login
                Pause-Menu
            }
            "M" { return }
            "Q" { exit 0 }
            "H" { Show-Help }
            "S" { Show-StatusScreen }
            "C" { }
            default { }
        }
    }
}

function Handle-InstallMenu {
    while ($true) {
        $choice = Show-InstallMenu

        switch ($choice) {
            "1" { Invoke-Script (Join-Path $script:RootDir "Scripts\Install-VSIX.ps1") -WaitForKey }
            "2" { Invoke-Script (Join-Path $script:RootDir "Scripts\Install-VSIX.ps1") -Parameters @{ Experimental = $true } -WaitForKey }
            "3" { Invoke-Script (Join-Path $script:RootDir "Scripts\Install-VSIX.ps1") -Parameters @{ Uninstall = $true } -WaitForKey }
            "4" { Invoke-Script (Join-Path $script:RootDir "Scripts\Install-VSIX.ps1") -Parameters @{ Experimental = $true; Launch = $true } -WaitForKey }
            "5" {
                $nupkg = Get-ChildItem -Path (Join-Path $script:RootDir "bin") -Filter "*.nupkg" -ErrorAction SilentlyContinue |
                         Sort-Object LastWriteTime -Descending | Select-Object -First 1
                if ($nupkg) {
                    Write-Host ""
                    Write-Host "  Installing: $($nupkg.Name)" -ForegroundColor Cyan
                    & dotnet new install $nupkg.FullName
                    Pause-Menu
                } else {
                    Write-Host "  No NuGet package found. Build first." -ForegroundColor Red
                    Pause-Menu
                }
            }
            "6" {
                Write-Host ""
                $packageId = Get-ConfigValue "nuget.packageId" "AlibreDesign.Templates"
                Write-Host "  Uninstalling: $packageId" -ForegroundColor Cyan
                & dotnet new uninstall $packageId
                Pause-Menu
            }
            "7" {
                Write-Host ""
                Write-Host "  Installed .NET Templates:" -ForegroundColor Cyan
                & dotnet new list --author (Get-ConfigValue "product.author" "")
                Pause-Menu
            }
            "8" {
                $installersPath = Join-Path $script:RootDir "Installers"
                $installers = Get-ChildItem -Path $installersPath -Filter "*.exe" -ErrorAction SilentlyContinue | Sort-Object Name
                if ($installers.Count -eq 0) {
                    Write-Host "  No installers found." -ForegroundColor Yellow
                    Pause-Menu
                } else {
                    Write-Host ""
                    Write-Host "  Select installer to run:" -ForegroundColor Cyan
                    for ($i = 0; $i -lt $installers.Count; $i++) {
                        Write-Host "    [$($i + 1)] $($installers[$i].Name)" -ForegroundColor White
                    }
                    Write-Host ""
                    Write-Host "  Enter number: " -NoNewline
                    $num = Read-Host
                    if ($num -match '^\d+$') {
                        $idx = [int]$num - 1
                        if ($idx -ge 0 -and $idx -lt $installers.Count) {
                            & $installers[$idx].FullName
                        }
                    }
                }
            }
            "9" {
                $installersPath = Join-Path $script:RootDir "Installers"
                Start-Process "explorer.exe" -ArgumentList $installersPath
            }
            "M" { return }
            "Q" { exit 0 }
            "H" { Show-Help }
            "S" { Show-StatusScreen }
            "C" { }
            default { }
        }
    }
}

# ==============================================================================
# MAIN LOOP
# ==============================================================================

# Quick mode shortcuts
if ($QuickBuild) {
    Invoke-Cmd (Join-Path $script:RootDir "build-full-with-installers.cmd")
    exit $LASTEXITCODE
}

if ($QuickRelease) {
    Invoke-Script (Join-Path $script:RootDir "Publish-Release.ps1") -Parameters @{ BuildFirst = $true }
    exit $LASTEXITCODE
}

# Main menu loop
while ($true) {
    $choice = Show-MainMenu

    switch ($choice) {
        "1" { Invoke-Cmd (Join-Path $script:RootDir "build-full-with-installers.cmd") -WaitForKey }
        "2" { Invoke-Script (Join-Path $script:RootDir "Build-All.ps1") -WaitForKey }
        "3" { Invoke-Script (Join-Path $script:RootDir "Build-Installers.ps1") -WaitForKey }
        "B" { Handle-BuildMenu }
        "T" { Handle-TestMenu }
        "R" { Handle-ReleaseMenu }
        "I" { Handle-InstallMenu }
        "P" { Show-ProjectList }
        "A" { Invoke-Script (Join-Path $script:RootDir "Generate-PipelineAudit.ps1") -WaitForKey }
        "O" { Start-Process "explorer.exe" -ArgumentList $script:RootDir }
        "Q" { exit 0 }
        "H" { Show-Help }
        "S" { Show-StatusScreen }
        "C" { }
        default { }
    }
}
