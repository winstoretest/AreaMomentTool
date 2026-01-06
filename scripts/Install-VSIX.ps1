<#
.SYNOPSIS
    Installs the Alibre Design VSIX extension for testing.

.DESCRIPTION
    This script automates the installation of the VSIX extension to Visual Studio
    for testing purposes. It can install to either the normal VS instance or the
    experimental instance (recommended for development).

    Features:
    - Automatically finds the VSIX file
    - Uninstalls previous versions before installing
    - Supports both VS 2022 and VS 2026
    - Can install to experimental instance for safe testing
    - Verifies installation success

    Visual Studio Instance Types:
    -----------------------------
    NORMAL INSTANCE: Your regular Visual Studio installation
        - Used for actual development work
        - Extensions persist across sessions
        - Changes affect your daily workflow

    EXPERIMENTAL INSTANCE: Isolated testing environment
        - Separate settings and extensions
        - Safe for testing unstable extensions
        - Can be reset without affecting normal VS
        - Launched with: devenv.exe /RootSuffix Exp

.PARAMETER VSIXPath
    Path to the VSIX file to install.
    If not specified, searches for the most recent VSIX in the build output.

.PARAMETER Experimental
    Install to the VS experimental instance (recommended for testing).
    This keeps your normal VS installation clean.

.PARAMETER VSVersion
    Target Visual Studio version: "2022" or "2026".
    If not specified, auto-detects installed versions.

.PARAMETER Uninstall
    Only uninstall the extension, don't install.

.PARAMETER Launch
    Launch Visual Studio after installation.
    Uses experimental instance if -Experimental was specified.

.EXAMPLE
    .\Install-VSIX.ps1

    Installs the latest VSIX to the normal VS instance.

.EXAMPLE
    .\Install-VSIX.ps1 -Experimental -Launch

    Installs to experimental instance and launches VS for testing.

.EXAMPLE
    .\Install-VSIX.ps1 -Uninstall

    Uninstalls the extension from VS.

.EXAMPLE
    .\Install-VSIX.ps1 -VSIXPath "C:\MyBuild\Extension.vsix" -VSVersion "2026"

    Installs specific VSIX to VS 2026.

.NOTES
    Author: Stephen S. Mitchell
    Version: 1.0.0
    Date: December 2025

    The VSIXInstaller.exe tool is used for installation. It's included with
    Visual Studio and handles all the complex extension deployment logic.

    Common exit codes from VSIXInstaller:
        0    - Success
        1001 - Extension already installed
        1002 - Extension not found
        2003 - VS instance is running (close VS first)

.LINK
    https://github.com/Testbed-for-Alibre-Design/AlibreExtensions
#>

# ==============================================================================
# SCRIPT PARAMETERS
# ==============================================================================

[CmdletBinding()]
param(
    # Path to VSIX file (auto-detected if not specified)
    [string]$VSIXPath,

    # Install to experimental instance
    [switch]$Experimental,

    # Target VS version
    [ValidateSet("2022", "2026", "")]
    [string]$VSVersion = "",

    # Uninstall only
    [switch]$Uninstall,

    # Launch VS after installation
    [switch]$Launch
)

# ==============================================================================
# CONFIGURATION
# ==============================================================================

$ErrorActionPreference = "Stop"

# Extension identifier (from vsixmanifest)
$ExtensionId = "AlibreDesignExtensions.e4a27de3-5208-4581-893a-9bf70e43f578"

# Script paths
$ScriptDir = $PSScriptRoot
$RootDir = (Resolve-Path (Join-Path $ScriptDir "..")).Path

# Default VSIX locations to search
$VSIXSearchPaths = @(
    (Join-Path $RootDir "bin\VSExtensionForAlibreDesign.vsix"),
    (Join-Path $RootDir "Extension\VSExtensionForAlibreDesign\bin\Release\VSExtensionForAlibreDesign.vsix"),
    (Join-Path $RootDir "Extension\VSExtensionForAlibreDesign\bin\Debug\VSExtensionForAlibreDesign.vsix")
)

# ==============================================================================
# HELPER FUNCTIONS
# ==============================================================================

function Write-Header {
    param([string]$Text)
    $line = "=" * 60
    Write-Host ""
    Write-Host $line -ForegroundColor Green
    Write-Host "  $Text" -ForegroundColor Green
    Write-Host $line -ForegroundColor Green
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

function Write-Failure {
    param([string]$Text)
    Write-Host "  [FAIL] $Text" -ForegroundColor Red
}

function Write-Info {
    param([string]$Text)
    Write-Host "  [i] $Text" -ForegroundColor Gray
}

function Find-VSInstallation {
    <#
    .SYNOPSIS
        Finds Visual Studio installation paths.

    .OUTPUTS
        Hashtable with VS installation details.
    #>
    param(
        [string]$PreferredVersion = ""
    )

    # Define search paths for different VS versions
    $vsSearchPaths = @(
        # VS 2026 paths
        @{
            Version = "2026"
            InternalVersion = "18"
            Paths = @(
                "C:\Program Files\Microsoft Visual Studio\2026\Enterprise",
                "C:\Program Files\Microsoft Visual Studio\2026\Professional",
                "C:\Program Files\Microsoft Visual Studio\2026\Community",
                "C:\Program Files\Microsoft Visual Studio\18\Enterprise",
                "C:\Program Files\Microsoft Visual Studio\18\Professional",
                "C:\Program Files\Microsoft Visual Studio\18\Community",
                "C:\Program Files\Microsoft Visual Studio\18\Insiders",
                "C:\Program Files\Microsoft Visual Studio\18\Preview"
            )
        },
        # VS 2022 paths
        @{
            Version = "2022"
            InternalVersion = "17"
            Paths = @(
                "C:\Program Files\Microsoft Visual Studio\2022\Enterprise",
                "C:\Program Files\Microsoft Visual Studio\2022\Professional",
                "C:\Program Files\Microsoft Visual Studio\2022\Community",
                "C:\Program Files\Microsoft Visual Studio\2022\Preview"
            )
        }
    )

    # If preferred version specified, search that first
    if ($PreferredVersion) {
        $vsSearchPaths = $vsSearchPaths | Where-Object { $_.Version -eq $PreferredVersion }
        $vsSearchPaths += $vsSearchPaths | Where-Object { $_.Version -ne $PreferredVersion }
    }

    foreach ($vsInfo in $vsSearchPaths) {
        foreach ($basePath in $vsInfo.Paths) {
            if (Test-Path $basePath) {
                $devenvPath = Join-Path $basePath "Common7\IDE\devenv.exe"
                $vsixInstallerPath = Join-Path $basePath "Common7\IDE\VSIXInstaller.exe"

                if ((Test-Path $devenvPath) -and (Test-Path $vsixInstallerPath)) {
                    return @{
                        Version = $vsInfo.Version
                        InternalVersion = $vsInfo.InternalVersion
                        BasePath = $basePath
                        DevEnvPath = $devenvPath
                        VSIXInstallerPath = $vsixInstallerPath
                        Edition = Split-Path $basePath -Leaf
                    }
                }
            }
        }
    }

    return $null
}

function Find-VSIXFile {
    <#
    .SYNOPSIS
        Finds the VSIX file to install.
    #>

    foreach ($path in $VSIXSearchPaths) {
        if (Test-Path $path) {
            return $path
        }
    }

    # Try to find any VSIX file in the Extension directory
    $extensionDir = Join-Path $RootDir "Extension"
    $vsixFiles = Get-ChildItem -Path $extensionDir -Filter "*.vsix" -Recurse -ErrorAction SilentlyContinue |
                 Sort-Object LastWriteTime -Descending

    if ($vsixFiles) {
        return $vsixFiles[0].FullName
    }

    return $null
}

function Test-VSRunning {
    <#
    .SYNOPSIS
        Checks if Visual Studio is currently running.
    #>
    param([string]$InternalVersion)

    $vsProcesses = Get-Process devenv -ErrorAction SilentlyContinue

    if ($vsProcesses) {
        # Check if any VS process matches our version
        foreach ($proc in $vsProcesses) {
            try {
                $procPath = $proc.Path
                if ($procPath -like "*$InternalVersion*" -or $procPath -like "*$($InternalVersion - 2000 + 2020)*") {
                    return $true
                }
            } catch {
                # Can't access process path, assume it might be our version
                return $true
            }
        }
    }

    return $false
}

function Invoke-VSIXInstaller {
    <#
    .SYNOPSIS
        Runs VSIXInstaller.exe with specified arguments.
    #>
    param(
        [string]$VSIXInstallerPath,
        [string[]]$Arguments
    )

    Write-Info "Running: VSIXInstaller.exe $($Arguments -join ' ')"

    $process = Start-Process -FilePath $VSIXInstallerPath `
                             -ArgumentList $Arguments `
                             -Wait `
                             -PassThru `
                             -NoNewWindow

    return $process.ExitCode
}

# ==============================================================================
# MAIN EXECUTION
# ==============================================================================

Write-Header "VSIX Extension Installer"

# ---------------------------------------------------------------------------
# STEP 1: Find Visual Studio installation
# ---------------------------------------------------------------------------

Write-Step "Finding Visual Studio installation..."

$vs = Find-VSInstallation -PreferredVersion $VSVersion

if (-not $vs) {
    throw "Visual Studio installation not found. Install VS 2022 or VS 2026."
}

Write-Info "Found: Visual Studio $($vs.Version) $($vs.Edition)"
Write-Info "Path: $($vs.BasePath)"
Write-Host ""

# ---------------------------------------------------------------------------
# STEP 2: Find VSIX file
# ---------------------------------------------------------------------------

if (-not $Uninstall) {
    Write-Step "Finding VSIX file..."

    if ($VSIXPath) {
        if (-not (Test-Path $VSIXPath)) {
            throw "VSIX file not found: $VSIXPath"
        }
    } else {
        $VSIXPath = Find-VSIXFile
        if (-not $VSIXPath) {
            throw "VSIX file not found. Build the project first: .\Build-Templates.ps1 -BuildVSIX"
        }
    }

    $vsixInfo = Get-Item $VSIXPath
    $vsixSize = [math]::Round($vsixInfo.Length / 1KB, 2)
    Write-Info "VSIX: $($vsixInfo.Name) ($vsixSize KB)"
    Write-Info "Modified: $($vsixInfo.LastWriteTime)"
    Write-Host ""
}

# ---------------------------------------------------------------------------
# STEP 3: Check if VS is running
# ---------------------------------------------------------------------------

Write-Step "Checking for running VS instances..."

if (Test-VSRunning -InternalVersion $vs.InternalVersion) {
    Write-Failure "Visual Studio is running!"
    Write-Host ""
    Write-Host "  Please close all Visual Studio windows before installing." -ForegroundColor Yellow
    Write-Host ""

    $response = Read-Host "  Close VS and continue? (y/n)"
    if ($response -ne "y" -and $response -ne "Y") {
        Write-Host "  Installation cancelled." -ForegroundColor Yellow
        exit 1
    }

    # Wait a moment for VS to close
    Start-Sleep -Seconds 2

    if (Test-VSRunning -InternalVersion $vs.InternalVersion) {
        throw "Visual Studio is still running. Please close it and try again."
    }
}

Write-Success "No conflicting VS instances found"
Write-Host ""

# ---------------------------------------------------------------------------
# STEP 4: Uninstall existing version
# ---------------------------------------------------------------------------

Write-Step "Uninstalling existing extension (if present)..."

$uninstallArgs = @("/uninstall:$ExtensionId", "/quiet")

if ($Experimental) {
    $uninstallArgs += "/rootSuffix:Exp"
}

$exitCode = Invoke-VSIXInstaller -VSIXInstallerPath $vs.VSIXInstallerPath -Arguments $uninstallArgs

# Exit code 2003 means extension not installed - that's OK
if ($exitCode -eq 0 -or $exitCode -eq 2003 -or $exitCode -eq 1002) {
    Write-Success "Uninstall completed"
} else {
    Write-Info "Uninstall returned code: $exitCode (continuing anyway)"
}
Write-Host ""

# ---------------------------------------------------------------------------
# STEP 5: Install new version (if not uninstall-only)
# ---------------------------------------------------------------------------

if (-not $Uninstall) {
    Write-Step "Installing extension..."

    $installArgs = @($VSIXPath, "/quiet")

    if ($Experimental) {
        $installArgs += "/rootSuffix:Exp"
        Write-Info "Installing to experimental instance"
    } else {
        Write-Info "Installing to normal instance"
    }

    $exitCode = Invoke-VSIXInstaller -VSIXInstallerPath $vs.VSIXInstallerPath -Arguments $installArgs

    if ($exitCode -eq 0) {
        Write-Success "Extension installed successfully!"
    } elseif ($exitCode -eq 1001) {
        Write-Success "Extension already installed (same version)"
    } else {
        Write-Failure "Installation failed with exit code: $exitCode"
        Write-Host ""
        Write-Host "  Common causes:" -ForegroundColor Yellow
        Write-Host "    - Visual Studio is still running" -ForegroundColor Gray
        Write-Host "    - VSIX file is corrupted" -ForegroundColor Gray
        Write-Host "    - Insufficient permissions" -ForegroundColor Gray
        Write-Host ""
        exit $exitCode
    }
    Write-Host ""
}

# ---------------------------------------------------------------------------
# STEP 6: Launch VS (if requested)
# ---------------------------------------------------------------------------

if ($Launch -and -not $Uninstall) {
    Write-Step "Launching Visual Studio..."

    $launchArgs = @()
    if ($Experimental) {
        $launchArgs = @("/RootSuffix", "Exp")
        Write-Info "Launching experimental instance"
    }

    Start-Process -FilePath $vs.DevEnvPath -ArgumentList $launchArgs
    Write-Success "Visual Studio launched"
    Write-Host ""
}

# ---------------------------------------------------------------------------
# SUMMARY
# ---------------------------------------------------------------------------

Write-Host "============================================================" -ForegroundColor Green
Write-Host "  INSTALLATION COMPLETE" -ForegroundColor Green
Write-Host "============================================================" -ForegroundColor Green
Write-Host ""

if ($Uninstall) {
    Write-Host "  Extension has been uninstalled." -ForegroundColor White
} else {
    Write-Host "  Extension: Alibre Design Extension for Visual Studio" -ForegroundColor White
    Write-Host "  Installed to: VS $($vs.Version) $($vs.Edition)" -ForegroundColor White
    if ($Experimental) {
        Write-Host "  Instance: Experimental" -ForegroundColor White
    } else {
        Write-Host "  Instance: Normal" -ForegroundColor White
    }
}

Write-Host ""
Write-Host "  To test:" -ForegroundColor Gray
Write-Host "    1. Open Visual Studio" -ForegroundColor White
Write-Host "    2. Go to: File > New > Project" -ForegroundColor White
Write-Host "    3. Search for: Alibre" -ForegroundColor White
Write-Host "    4. You should see the Alibre Design templates" -ForegroundColor White
Write-Host ""

if ($Experimental -and -not $Launch) {
    Write-Host "  To launch experimental instance:" -ForegroundColor Gray
    Write-Host "    devenv.exe /RootSuffix Exp" -ForegroundColor White
    Write-Host ""
}
