<#
.SYNOPSIS
    Builds installers and publishes GitHub releases for Alibre Design addon projects.

.DESCRIPTION
    This script automates the build-and-release workflow for individual addon projects.
    It discovers projects, builds their installers using Build-Installers.ps1, and
    publishes them as GitHub releases.

    WORKFLOW:
    1. Discovers projects in Working/Projects/
    2. Builds installers (calls Build-Installers.ps1)
    3. Matches installers to projects by name
    4. Publishes each installer to its project's GitHub repo

    REPOSITORY DETECTION:
    - If project folder has .git subfolder, uses that repo
    - Otherwise, looks for a release.config.json in project folder
    - Fallback: uses main repo with project-specific tag

.PARAMETER Project
    Project folder name to release (e.g., "alibre-export-addon").
    If not specified, processes all projects with installers.

.PARAMETER BuildFirst
    Build installers before publishing (runs Build-Installers.ps1).

.PARAMETER Tag
    Release tag override. Defaults to v{version} from build.config.json.

.PARAMETER Draft
    Create as draft release.

.PARAMETER Prerelease
    Mark as prerelease.

.PARAMETER GenerateNotes
    Auto-generate release notes from commits.

.PARAMETER ListProjects
    List all projects and their repo status, then exit.

.PARAMETER Force
    Overwrite existing releases.

.PARAMETER WhatIf
    Show what would be done without making changes.

.EXAMPLE
    .\Publish-Release.ps1 -Project "alibre-export-addon"

    Publishes the alibre-export-addon installer.

.EXAMPLE
    .\Publish-Release.ps1 -BuildFirst

    Builds all installers then publishes them.

.EXAMPLE
    .\Publish-Release.ps1 -ListProjects

    Shows all projects and their GitHub repo configuration.

.EXAMPLE
    .\Publish-Release.ps1 -Project "alibre-export-addon" -BuildFirst -Draft

    Builds and creates a draft release for one project.

.NOTES
    PREREQUISITES:
    - GitHub CLI (gh): https://cli.github.com/
    - Inno Setup 6: https://jrsoftware.org/isdl.php
    - Must be authenticated: gh auth login

    PROJECT REPO CONFIGURATION:
    Create release.config.json in project folder:
    {
        "repo": "owner/repo-name",
        "branch": "main"
    }

    Author: Stephen S. Mitchell
    Version: 1.0.0
#>

[CmdletBinding(SupportsShouldProcess)]
param(
    [string]$Project,
    [switch]$BuildFirst,
    [string]$Tag,
    [switch]$Draft,
    [switch]$Prerelease,
    [switch]$GenerateNotes,
    [switch]$ListProjects,
    [switch]$Force
)

$ErrorActionPreference = "Stop"

# ==============================================================================
# CONFIGURATION
# ==============================================================================

$script:RootDir = $PSScriptRoot
if (-not $script:RootDir) {
    $script:RootDir = Split-Path -Parent $MyInvocation.MyCommand.Path
}

# Load build config
$script:ConfigPath = Join-Path $script:RootDir "build.config.json"
if (Test-Path $script:ConfigPath) {
    $script:Config = Get-Content $script:ConfigPath -Raw | ConvertFrom-Json
} else {
    $script:Config = $null
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

# Version
$script:VersionMajor = Get-ConfigValue "version.major" 1
$script:VersionMinor = Get-ConfigValue "version.minor" 0
$script:VersionPatch = Get-ConfigValue "version.patch" 0
$script:Version = "$script:VersionMajor.$script:VersionMinor.$script:VersionPatch"

# Paths
$script:Paths = @{
    Root       = $script:RootDir
    Projects   = Join-Path $script:RootDir (Get-ConfigValue "paths.working" "Working/Projects")
    Installers = Join-Path $script:RootDir (Get-ConfigValue "paths.installers" "Installers")
    Bin        = Join-Path $script:RootDir (Get-ConfigValue "paths.bin" "bin")
}

# Default GitHub org/owner for repos without explicit config
$script:DefaultOwner = Get-ConfigValue "product.publisher" "Testbed-for-Alibre-Design"
$script:DefaultRepoBase = Get-ConfigValue "product.projectUrl" "https://github.com/Testbed-for-Alibre-Design/AlibreExtensions"

# ==============================================================================
# CONSOLE OUTPUT
# ==============================================================================

function Write-Banner {
    $banner = @"

================================================================================
  ALIBRE DESIGN RELEASE PUBLISHER
  Version: $script:Version
================================================================================
  Projects: $($script:Paths.Projects)
  Installers: $($script:Paths.Installers)
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

# ==============================================================================
# PREREQUISITES
# ==============================================================================

function Test-GitHubCLI {
    $gh = Get-Command "gh" -ErrorAction SilentlyContinue
    if (-not $gh) {
        throw @"
GitHub CLI (gh) is not installed.

Install: winget install GitHub.cli
Then: gh auth login
"@
    }

    $authStatus = & gh auth status 2>&1
    if ($LASTEXITCODE -ne 0) {
        throw "GitHub CLI not authenticated. Run: gh auth login"
    }
    return $true
}

# ==============================================================================
# PROJECT DISCOVERY
# ==============================================================================

function Get-ProjectInfo {
    <#
    .SYNOPSIS
        Discovers all projects and their repo configuration.
    #>
    param([string]$FilterName = "*")

    $projects = @()

    if (-not (Test-Path $script:Paths.Projects)) {
        Write-Failure "Projects directory not found: $($script:Paths.Projects)"
        return $projects
    }

    $projectFolders = Get-ChildItem -Path $script:Paths.Projects -Directory |
                      Where-Object { $_.Name -like $FilterName -and $_.Name -notmatch "^(bin|obj|\.vs|nul|Solution)$" }

    foreach ($folder in $projectFolders) {
        $projectPath = $folder.FullName
        $projectName = $folder.Name

        # Check for project files
        $projFiles = Get-ChildItem -Path $projectPath -Include "*.csproj", "*.vbproj", "*.fsproj" -Recurse -ErrorAction SilentlyContinue |
                     Where-Object { $_.FullName -notmatch "\\(bin|obj)\\" } |
                     Select-Object -First 1

        if (-not $projFiles) { continue }

        # Check for .iss file
        $issFile = Get-ChildItem -Path $projectPath -Filter "*.iss" -Recurse -ErrorAction SilentlyContinue |
                   Where-Object { $_.FullName -notmatch "\\(bin|obj)\\" } |
                   Select-Object -First 1

        # Check for .adc file to get friendly name
        $adcFile = Get-ChildItem -Path $projectPath -Filter "*.adc" -ErrorAction SilentlyContinue |
                   Where-Object { $_.FullName -notmatch "\\(bin|obj)\\" } |
                   Select-Object -First 1

        $friendlyName = $projectName
        if ($adcFile) {
            try {
                [xml]$adcXml = Get-Content $adcFile.FullName
                if ($adcXml.AlibreDesignAddOn.friendlyName) {
                    $friendlyName = $adcXml.AlibreDesignAddOn.friendlyName
                }
            } catch { }
        }

        # Check for own git repo
        $hasOwnRepo = Test-Path (Join-Path $projectPath ".git")
        $repoUrl = $null
        $repoOwner = $null
        $repoName = $null

        if ($hasOwnRepo) {
            # Get remote URL from project's own git repo
            Push-Location $projectPath
            try {
                $remoteUrl = & git remote get-url origin 2>$null
                if ($remoteUrl) {
                    $repoUrl = $remoteUrl
                    # Parse owner/repo from URL
                    if ($remoteUrl -match "github\.com[:/]([^/]+)/([^/.]+)") {
                        $repoOwner = $Matches[1]
                        $repoName = $Matches[2]
                    }
                }
            } catch { }
            finally { Pop-Location }
        }

        # Check for release.config.json
        $releaseConfigPath = Join-Path $projectPath "release.config.json"
        $releaseConfig = $null
        if (Test-Path $releaseConfigPath) {
            try {
                $releaseConfig = Get-Content $releaseConfigPath -Raw | ConvertFrom-Json
                if ($releaseConfig.repo) {
                    $parts = $releaseConfig.repo -split "/"
                    if ($parts.Count -ge 2) {
                        $repoOwner = $parts[0]
                        $repoName = $parts[1]
                        $repoUrl = "https://github.com/$($releaseConfig.repo)"
                    }
                }
            } catch { }
        }

        # Fallback: assume repo name matches project folder name under default owner
        if (-not $repoOwner) {
            $repoOwner = $script:DefaultOwner
            $repoName = $projectName
            $repoUrl = "https://github.com/$repoOwner/$repoName"
        }

        # Find matching installer
        $installerPattern = "$friendlyName-*-Setup.exe"
        $installer = Get-ChildItem -Path $script:Paths.Installers -Filter $installerPattern -ErrorAction SilentlyContinue |
                     Sort-Object LastWriteTime -Descending |
                     Select-Object -First 1

        # Also try matching by project name if friendly name didn't match
        if (-not $installer -and $friendlyName -ne $projectName) {
            $installerPattern = "$projectName-*-Setup.exe"
            $installer = Get-ChildItem -Path $script:Paths.Installers -Filter $installerPattern -ErrorAction SilentlyContinue |
                         Sort-Object LastWriteTime -Descending |
                         Select-Object -First 1
        }

        $project = @{
            Name          = $projectName
            FriendlyName  = $friendlyName
            Path          = $projectPath
            ProjectFile   = $projFiles.FullName
            IssFile       = if ($issFile) { $issFile.FullName } else { $null }
            AdcFile       = if ($adcFile) { $adcFile.FullName } else { $null }
            HasOwnRepo    = $hasOwnRepo
            RepoUrl       = $repoUrl
            RepoOwner     = $repoOwner
            RepoName      = $repoName
            RepoFullName  = "$repoOwner/$repoName"
            Installer     = if ($installer) { $installer.FullName } else { $null }
            InstallerName = if ($installer) { $installer.Name } else { $null }
            HasInstaller  = ($null -ne $installer)
            ReleaseConfig = $releaseConfig
        }

        $projects += $project
    }

    return $projects
}

function Show-ProjectList {
    param([array]$Projects)

    Write-Section "PROJECT INVENTORY"

    $hasInstaller = $Projects | Where-Object { $_.HasInstaller }
    $noInstaller = $Projects | Where-Object { -not $_.HasInstaller }
    $hasOwnRepo = $Projects | Where-Object { $_.HasOwnRepo }

    Write-Host "  Total Projects: $($Projects.Count)" -ForegroundColor White
    Write-Host "  With Installers: $($hasInstaller.Count)" -ForegroundColor Green
    Write-Host "  Without Installers: $($noInstaller.Count)" -ForegroundColor Yellow
    Write-Host "  With Own Git Repo: $($hasOwnRepo.Count)" -ForegroundColor Cyan
    Write-Host ""

    Write-Host "  " + ("-" * 74) -ForegroundColor DarkGray
    Write-Host ("  {0,-35} {1,-25} {2}" -f "PROJECT", "REPO", "INSTALLER") -ForegroundColor White
    Write-Host "  " + ("-" * 74) -ForegroundColor DarkGray

    foreach ($proj in ($Projects | Sort-Object Name)) {
        $repoLabel = if ($proj.HasOwnRepo) { "[own] " + $proj.RepoName } else { $proj.RepoFullName }
        if ($repoLabel.Length -gt 25) { $repoLabel = $repoLabel.Substring(0, 22) + "..." }

        $installerLabel = if ($proj.HasInstaller) { "YES" } else { "-" }
        $color = if ($proj.HasInstaller) { "Green" } else { "DarkGray" }

        Write-Host ("  {0,-35} {1,-25} {2}" -f $proj.Name, $repoLabel, $installerLabel) -ForegroundColor $color
    }

    Write-Host "  " + ("-" * 74) -ForegroundColor DarkGray
    Write-Host ""
}

# ==============================================================================
# BUILD INSTALLERS
# ==============================================================================

function Invoke-BuildInstallers {
    param([string]$ProjectFilter = "*")

    Write-Section "BUILDING INSTALLERS"

    $buildScript = Join-Path $script:RootDir "Build-Installers.ps1"
    if (-not (Test-Path $buildScript)) {
        throw "Build-Installers.ps1 not found at: $buildScript"
    }

    Write-Step "Running Build-Installers.ps1..."

    $buildArgs = @{
        Configuration = "Release"
    }

    if ($ProjectFilter -ne "*") {
        $buildArgs["ProjectFilter"] = $ProjectFilter
    }

    & $buildScript @buildArgs

    if ($LASTEXITCODE -ne 0) {
        throw "Build-Installers.ps1 failed with exit code $LASTEXITCODE"
    }

    Write-Success "Build completed"
}

# ==============================================================================
# GITHUB RELEASE
# ==============================================================================

function Publish-ProjectRelease {
    param(
        [hashtable]$Project,
        [string]$Tag,
        [switch]$Draft,
        [switch]$Prerelease,
        [switch]$GenerateNotes,
        [switch]$Force
    )

    $projectName = $Project.Name
    $repoFullName = $Project.RepoFullName
    $installerPath = $Project.Installer

    Write-Step "Publishing: $projectName"
    Write-SubStep "Repository: $repoFullName"
    Write-SubStep "Installer: $($Project.InstallerName)"

    # Determine tag
    if (-not $Tag) {
        $Tag = "v$script:Version"
    }

    Write-SubStep "Tag: $Tag"

    # Check if release already exists
    $existingRelease = & gh release view $Tag --repo $repoFullName 2>&1
    if ($LASTEXITCODE -eq 0) {
        if ($Force) {
            Write-SubStep "Deleting existing release..."
            if ($PSCmdlet.ShouldProcess($Tag, "Delete existing release from $repoFullName")) {
                & gh release delete $Tag --repo $repoFullName --yes 2>&1 | Out-Null
            }
        } else {
            Write-Failure "Release $Tag already exists. Use -Force to overwrite."
            return @{ Success = $false; Error = "Release exists" }
        }
    }

    # Build gh release create command
    $ghArgs = @(
        "release", "create", $Tag,
        "--repo", $repoFullName,
        "--title", "$($Project.FriendlyName) $Tag"
    )

    # Release notes
    if ($GenerateNotes) {
        $ghArgs += "--generate-notes"
    } else {
        $notes = @"
## $($Project.FriendlyName) $Tag

### Installation

1. Download the installer below
2. Run the installer
3. Restart Alibre Design

### Downloads

- **$($Project.InstallerName)** - Windows Installer
"@
        $ghArgs += "--notes"
        $ghArgs += $notes
    }

    # Flags
    if ($Draft) { $ghArgs += "--draft" }
    if ($Prerelease) { $ghArgs += "--prerelease" }

    # Add installer file
    $ghArgs += $installerPath

    # Create release
    if ($PSCmdlet.ShouldProcess("$repoFullName $Tag", "Create GitHub release")) {
        Write-SubStep "Creating release..."

        $result = & gh @ghArgs 2>&1

        if ($LASTEXITCODE -ne 0) {
            Write-Failure "Failed to create release"
            Write-Host "    $result" -ForegroundColor Red
            return @{ Success = $false; Error = $result }
        }

        # Get release URL
        $releaseUrl = & gh release view $Tag --repo $repoFullName --json url -q ".url" 2>&1

        Write-Success "Release created: $releaseUrl"

        return @{
            Success = $true
            Tag = $Tag
            Url = $releaseUrl
            Repo = $repoFullName
        }
    } else {
        Write-Info "WhatIf: Would create release $Tag on $repoFullName"
        return @{ Success = $true; WhatIf = $true }
    }
}

# ==============================================================================
# MAIN EXECUTION
# ==============================================================================

try {
    Write-Banner

    # Check prerequisites
    Write-Section "CHECKING PREREQUISITES"

    Write-Step "Checking GitHub CLI..."
    Test-GitHubCLI | Out-Null
    Write-Success "GitHub CLI ready"

    # Discover projects
    Write-Section "DISCOVERING PROJECTS"

    $filterName = if ($Project) { $Project } else { "*" }
    $projects = Get-ProjectInfo -FilterName $filterName

    if ($projects.Count -eq 0) {
        if ($Project) {
            throw "Project not found: $Project"
        } else {
            throw "No projects found in: $($script:Paths.Projects)"
        }
    }

    Write-Success "Found $($projects.Count) project(s)"

    # List mode
    if ($ListProjects) {
        Show-ProjectList -Projects $projects
        exit 0
    }

    # Build installers if requested
    if ($BuildFirst) {
        $buildFilter = if ($Project) { $Project } else { "*" }
        Invoke-BuildInstallers -ProjectFilter $buildFilter

        # Re-discover to pick up new installers
        $projects = Get-ProjectInfo -FilterName $filterName
    }

    # Filter to projects with installers
    $releasableProjects = $projects | Where-Object { $_.HasInstaller }

    if ($releasableProjects.Count -eq 0) {
        Write-Info "No installers found. Run with -BuildFirst to build them."
        Show-ProjectList -Projects $projects
        exit 0
    }

    Write-Section "PUBLISHING RELEASES"

    $results = @()

    foreach ($proj in $releasableProjects) {
        $result = Publish-ProjectRelease `
            -Project $proj `
            -Tag $Tag `
            -Draft:$Draft `
            -Prerelease:$Prerelease `
            -GenerateNotes:$GenerateNotes `
            -Force:$Force

        $results += @{
            Project = $proj.Name
            Success = $result.Success
            Tag = $result.Tag
            Url = $result.Url
            Error = $result.Error
        }
    }

    # Summary
    Write-Host ""
    Write-Host ("=" * 78) -ForegroundColor Green
    Write-Host "  RELEASE COMPLETE" -ForegroundColor Green
    Write-Host ("=" * 78) -ForegroundColor Green
    Write-Host ""

    $successCount = ($results | Where-Object { $_.Success }).Count
    $failCount = ($results | Where-Object { -not $_.Success }).Count

    Write-Host "  Results: $successCount succeeded, $failCount failed" -ForegroundColor White
    Write-Host ""

    foreach ($r in ($results | Where-Object { $_.Success })) {
        Write-Host "  [OK] $($r.Project)" -ForegroundColor Green
        if ($r.Url) {
            Write-Host "       $($r.Url)" -ForegroundColor Cyan
        }
    }

    foreach ($r in ($results | Where-Object { -not $_.Success })) {
        Write-Host "  [FAIL] $($r.Project): $($r.Error)" -ForegroundColor Red
    }

    Write-Host ""

    if ($failCount -gt 0) {
        exit 1
    }
}
catch {
    Write-Host ""
    Write-Host "PUBLISH FAILED: $_" -ForegroundColor Red
    Write-Host $_.ScriptStackTrace -ForegroundColor DarkRed
    exit 1
}
