<#
.SYNOPSIS
    Signs the AreaMomentTool installer and uploads to GitHub Pages.

.DESCRIPTION
    Downloads the unsigned installer from GitHub Pages, signs it with a
    hardware token certificate, and uploads the signed version.

.PARAMETER Version
    Version number (e.g., 1.0.0). Default is 1.0.0.

.PARAMETER CertificateThumbprint
    SHA1 thumbprint of the code signing certificate.

.PARAMETER TimestampUrl
    Timestamp server URL. Default is Sectigo's server.

.PARAMETER SkipUpload
    Sign only, don't upload to GitHub Pages.

.EXAMPLE
    .\Sign-Release.ps1 -Version "1.0.0" -CertificateThumbprint "ABC123..."

.EXAMPLE
    .\Sign-Release.ps1 -Version "1.0.0" -CertificateThumbprint "ABC123..." -SkipUpload
#>

[CmdletBinding()]
param(
    [string]$Version = "1.0.0",
    [string]$CertificateThumbprint,
    [string]$TimestampUrl = "http://timestamp.sectigo.com",
    [switch]$SkipUpload
)

$ErrorActionPreference = "Stop"

# Configuration
$RepoRoot = Split-Path -Parent $PSScriptRoot
$InstallerName = "AreaMomentTool-$Version-Setup.exe"
$GitHubRepo = "winstoretest/AreaMomentTool"
$DownloadUrl = "https://github.com/$GitHubRepo/releases/download/v$Version/$InstallerName"
$TempDir = Join-Path $env:TEMP "AreaMomentTool-Sign"
$InstallerPath = Join-Path $TempDir $InstallerName

# ==============================================================================
# FUNCTIONS
# ==============================================================================

function Write-Step {
    param([string]$Text)
    Write-Host "[*] $Text" -ForegroundColor Cyan
}

function Write-Success {
    param([string]$Text)
    Write-Host "[OK] $Text" -ForegroundColor Green
}

function Write-Failure {
    param([string]$Text)
    Write-Host "[FAIL] $Text" -ForegroundColor Red
}

function Find-SignTool {
    # Search Windows SDK paths
    $sdkRoot = "C:\Program Files (x86)\Windows Kits\10\bin"
    if (Test-Path $sdkRoot) {
        $versions = Get-ChildItem -Path $sdkRoot -Directory |
                    Where-Object { $_.Name -match '^\d+\.\d+\.\d+\.\d+$' } |
                    Sort-Object { [version]$_.Name } -Descending

        foreach ($version in $versions) {
            $signToolPath = Join-Path $version.FullName "x64\signtool.exe"
            if (Test-Path $signToolPath) {
                return $signToolPath
            }
        }
    }

    # Try PATH
    $signTool = Get-Command "signtool.exe" -ErrorAction SilentlyContinue
    if ($signTool) {
        return $signTool.Path
    }

    return $null
}

# ==============================================================================
# MAIN
# ==============================================================================

Write-Host ""
Write-Host "======================================" -ForegroundColor Cyan
Write-Host "  AreaMomentTool Release Signer" -ForegroundColor Cyan
Write-Host "======================================" -ForegroundColor Cyan
Write-Host ""
Write-Host "  Version: $Version"
Write-Host "  Installer: $InstallerName"
Write-Host ""

# Validate thumbprint
if (-not $CertificateThumbprint) {
    Write-Failure "Certificate thumbprint is required. Use -CertificateThumbprint parameter."
    Write-Host ""
    Write-Host "To find your certificate thumbprint:" -ForegroundColor Yellow
    Write-Host '  certutil -store My | findstr "Cert Hash"' -ForegroundColor Gray
    Write-Host ""
    exit 1
}

# Find SignTool
Write-Step "Finding SignTool..."
$signTool = Find-SignTool
if (-not $signTool) {
    Write-Failure "SignTool not found. Install Windows SDK."
    exit 1
}
Write-Success "Found: $signTool"

# Create temp directory
if (-not (Test-Path $TempDir)) {
    New-Item -ItemType Directory -Path $TempDir -Force | Out-Null
}

# Download installer from GitHub Releases
Write-Step "Downloading unsigned installer from GitHub Releases..."
Write-Host "  URL: $DownloadUrl" -ForegroundColor Gray
try {
    # GitHub releases redirect, need to follow redirects
    $webClient = New-Object System.Net.WebClient
    $webClient.Headers.Add("User-Agent", "PowerShell")
    $webClient.DownloadFile($DownloadUrl, $InstallerPath)
    $fileSize = (Get-Item $InstallerPath).Length / 1KB
    Write-Success "Downloaded ($([math]::Round($fileSize, 2)) KB)"
} catch {
    Write-Failure "Download failed: $_"
    Write-Host "  Make sure release v$Version exists at:" -ForegroundColor Yellow
    Write-Host "  https://github.com/$GitHubRepo/releases/tag/v$Version" -ForegroundColor Yellow
    exit 1
}

# Sign installer
Write-Step "Signing installer (make sure your USB token is plugged in)..."
Write-Host "  Certificate: $($CertificateThumbprint.Substring(0, 8))..." -ForegroundColor Gray
Write-Host "  Timestamp: $TimestampUrl" -ForegroundColor Gray

$signArgs = @(
    "sign",
    "/sha1", $CertificateThumbprint,
    "/fd", "sha256",
    "/tr", $TimestampUrl,
    "/td", "sha256",
    "/v",
    "`"$InstallerPath`""
)

$process = Start-Process -FilePath $signTool -ArgumentList $signArgs -Wait -PassThru -NoNewWindow
if ($process.ExitCode -ne 0) {
    Write-Failure "Signing failed (exit code $($process.ExitCode))"
    exit 1
}
Write-Success "Installer signed successfully"

# Verify signature
Write-Step "Verifying signature..."
$verifyArgs = @("verify", "/pa", "/v", "`"$InstallerPath`"")
$process = Start-Process -FilePath $signTool -ArgumentList $verifyArgs -Wait -PassThru -NoNewWindow
if ($process.ExitCode -eq 0) {
    Write-Success "Signature verified"
} else {
    Write-Failure "Signature verification failed"
    exit 1
}

if ($SkipUpload) {
    Write-Host ""
    Write-Success "Signed installer saved to: $InstallerPath"
    Write-Host ""
    exit 0
}

# Upload to GitHub Pages
Write-Step "Uploading to GitHub Pages..."

Push-Location $RepoRoot
try {
    # Fetch gh-pages
    git fetch origin gh-pages 2>$null

    # Checkout gh-pages branch
    $checkoutResult = git checkout gh-pages 2>&1
    if ($LASTEXITCODE -ne 0) {
        # Try to create from remote
        git checkout -B gh-pages origin/gh-pages 2>$null
        if ($LASTEXITCODE -ne 0) {
            throw "Could not checkout gh-pages branch. Run the GitHub Actions workflow first."
        }
    }

    git pull origin gh-pages 2>$null

    # Copy signed installer
    Copy-Item $InstallerPath -Destination . -Force

    # Commit and push (use -f to override .gitignore)
    git add -f $InstallerName
    git commit -m "Add signed installer v$Version"
    git push origin gh-pages

    Write-Success "Uploaded to GitHub Pages"

    # Switch back to main
    git checkout main
} catch {
    Write-Failure "Upload failed: $_"
    git checkout main 2>$null
    exit 1
} finally {
    Pop-Location
}

Write-Host ""
Write-Host "  Signed installer also saved at:" -ForegroundColor Gray
Write-Host "  $InstallerPath" -ForegroundColor Gray

Write-Host ""
Write-Host "======================================" -ForegroundColor Green
Write-Host "  SIGNING COMPLETE" -ForegroundColor Green
Write-Host "======================================" -ForegroundColor Green
Write-Host ""
Write-Host "  Signed installer URL:" -ForegroundColor White
Write-Host "  https://winstoretest.github.io/AreaMomentTool/$InstallerName" -ForegroundColor Yellow
Write-Host ""
Write-Host "  Use this URL for Microsoft Store submission." -ForegroundColor Gray
Write-Host ""
