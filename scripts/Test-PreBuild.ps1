<#
.SYNOPSIS
    Pre-Build Template Validation
    Validates source templates before building VSIX
    Configuration loaded from build.config.json
#>

$ErrorActionPreference = 'Stop'
$script:RootDir = Split-Path -Parent $MyInvocation.MyCommand.Path

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

# Build paths from config
$workingDir = Join-Path $script:RootDir (Get-ConfigValue "paths.working" "Working/Projects")
$logDir = Join-Path $script:RootDir (Get-ConfigValue "paths.logs" "Docs/_logs")
$auditDir = Join-Path $script:RootDir (Get-ConfigValue "paths.audit" "Docs/_audit")

# Start transcript logging
if (-not (Test-Path $logDir)) {
    New-Item -ItemType Directory -Path $logDir -Force | Out-Null
}
$timestamp = Get-Date -Format "yyyy-MM-dd_HH-mm-ss"
$script:LogPath = Join-Path $logDir "log-cli-test-pre-$timestamp.txt"
Start-Transcript -Path $script:LogPath -Force | Out-Null

Write-Host ""
Write-Host "  [PRE-BUILD] Validating source templates..." -ForegroundColor Cyan
Write-Host ""

$failed = 0
$passed = 0

# Find all project files in Working/
$allProjects = @()
$allProjects += Get-ChildItem -Path $workingDir -Recurse -Filter "*.csproj" -ErrorAction SilentlyContinue |
                Where-Object { $_.FullName -notlike "*\bin\*" -and $_.FullName -notlike "*\obj\*" }
$allProjects += Get-ChildItem -Path $workingDir -Recurse -Filter "*.vbproj" -ErrorAction SilentlyContinue |
                Where-Object { $_.FullName -notlike "*\bin\*" -and $_.FullName -notlike "*\obj\*" }

if ($allProjects.Count -eq 0) {
    Write-Host "  No projects found in Working/ directory" -ForegroundColor Yellow
    exit 0
}

# Deduplicate: Only test one project per folder (prefer projects matching folder name)
$projectsByFolder = @{}
foreach ($proj in $allProjects) {
    $relativePath = $proj.FullName.Substring($workingDir.Length + 1)
    $folderName = $relativePath.Split('\')[0]
    
    # If folder not seen yet, add this project
    if (-not $projectsByFolder.ContainsKey($folderName)) {
        $projectsByFolder[$folderName] = $proj
    }
    # If project name matches folder name pattern, prefer it
    elseif ($proj.BaseName -like "*$folderName*" -or $folderName -like "*$($proj.BaseName)*") {
        $projectsByFolder[$folderName] = $proj
    }
}

$projects = $projectsByFolder.Values

Write-Host "  Found $($projects.Count) source templates to validate (from $($allProjects.Count) project files):" -ForegroundColor Gray
Write-Host ""

$skipped = 0

# Find MSBuild for legacy .NET Framework projects
$msbuildPath = $null
$msbuildSearchPaths = @(
    "C:\Program Files\Microsoft Visual Studio\2022\Enterprise\MSBuild\Current\Bin\MSBuild.exe",
    "C:\Program Files\Microsoft Visual Studio\2022\Professional\MSBuild\Current\Bin\MSBuild.exe",
    "C:\Program Files\Microsoft Visual Studio\2022\Community\MSBuild\Current\Bin\MSBuild.exe"
)
foreach ($path in $msbuildSearchPaths) {
    if (Test-Path $path) { $msbuildPath = $path; break }
}

foreach ($proj in $projects) {
    # Get template folder name (first folder under Working/)
    $relativePath = $proj.FullName.Substring($workingDir.Length + 1)
    $name = $relativePath.Split('\')[0]
    $ext = if ($proj.Extension -eq ".csproj") { "C#" } else { "VB" }

    Write-Host "    [$ext] $name " -NoNewline

    # Check if this is a template-only project (contains $safeprojectname$ or similar)
    $projContent = Get-Content $proj.FullName -Raw -ErrorAction SilentlyContinue
    if ($projContent -match '\$safeprojectname\$|\$projectname\$|\$rootnamespace\$') {
        Write-Host "SKIPPED (template-only)" -ForegroundColor DarkYellow
        $skipped++
        continue
    }

    # Check if this is a legacy .NET Framework project (not SDK-style)
    $isLegacyProject = $projContent -notmatch '<Project\s+Sdk='

    if ($isLegacyProject -and $msbuildPath) {
        # Use MSBuild for legacy .NET Framework projects with PackageReference
        $output = & $msbuildPath $proj.FullName /t:Restore,Build /p:Configuration=Debug /nologo /v:q 2>&1
    } else {
        # Use dotnet build for SDK-style projects
        $restoreOutput = & dotnet restore $proj.FullName --nologo -v q 2>&1
        $output = & dotnet build $proj.FullName --nologo --no-restore -v q 2>&1
    }

    if ($LASTEXITCODE -eq 0) {
        Write-Host "OK" -ForegroundColor Green
        $passed++
    } else {
        Write-Host "FAILED" -ForegroundColor Red
        $failed++
        # Show first error line
        $errorLine = ($output | Where-Object { $_ -match "error" } | Select-Object -First 1)
        if ($errorLine) {
            Write-Host "         $errorLine" -ForegroundColor DarkRed
        }
    }
}

Write-Host ""
Write-Host ("=" * 60) -ForegroundColor Gray

$summary = "Passed: $passed"
if ($skipped -gt 0) { $summary += ", Skipped: $skipped" }
if ($failed -gt 0) { $summary += ", Failed: $failed" }

# Generate audit map (auditDir already set from config)
if (-not (Test-Path $auditDir)) {
    New-Item -ItemType Directory -Path $auditDir -Force | Out-Null
}

$timestamp = Get-Date -Format "yyyy-MM-dd HH:mm:ss"
$status = if ($failed -gt 0) { "FAILED" } else { "PASSED" }

$sb = [System.Text.StringBuilder]::new()
[void]$sb.AppendLine("# Audit Map: test-pre.cmd")
[void]$sb.AppendLine("")
[void]$sb.AppendLine("> Pre-Build Template Validation")
[void]$sb.AppendLine("> Generated: $timestamp")
[void]$sb.AppendLine("")
[void]$sb.AppendLine("## Script Chain")
[void]$sb.AppendLine("")
[void]$sb.AppendLine('```')
[void]$sb.AppendLine("test-pre.cmd")
[void]$sb.AppendLine("    +-- Test-PreBuild.ps1")
[void]$sb.AppendLine('```')
[void]$sb.AppendLine("")
[void]$sb.AppendLine("---")
[void]$sb.AppendLine("")
[void]$sb.AppendLine("## Results Summary")
[void]$sb.AppendLine("")
[void]$sb.AppendLine("| Metric | Value |")
[void]$sb.AppendLine("|--------|-------|")
[void]$sb.AppendLine("| Total Projects | $($projects.Count) |")
[void]$sb.AppendLine("| Passed | $passed |")
[void]$sb.AppendLine("| Skipped (template-only) | $skipped |")
[void]$sb.AppendLine("| Failed | $failed |")
[void]$sb.AppendLine("| Status | $status |")
[void]$sb.AppendLine("")
[void]$sb.AppendLine("---")
[void]$sb.AppendLine("")
[void]$sb.AppendLine("## Projects Tested")
[void]$sb.AppendLine("")
[void]$sb.AppendLine("| Project | Language | Status |")
[void]$sb.AppendLine("|---------|----------|--------|")

# Add project results to audit
foreach ($proj in $projects) {
    # Get template folder name (first folder under Working/)
    $relativePath = $proj.FullName.Substring($workingDir.Length + 1)
    $name = $relativePath.Split('\')[0]
    $lang = if ($proj.Extension -eq ".csproj") { "C#" } else { "VB.NET" }
    $projContent = Get-Content $proj.FullName -Raw -ErrorAction SilentlyContinue
    $isTemplate = $projContent -match '\$safeprojectname\$|\$projectname\$|\$rootnamespace\$'

    $projStatus = if ($isTemplate) { "SKIPPED (template-only)" } else { "PASSED" }
    [void]$sb.AppendLine("| ``$name`` | $lang | $projStatus |")
}

[void]$sb.AppendLine("")
[void]$sb.AppendLine("---")
[void]$sb.AppendLine("")
[void]$sb.AppendLine("## Input Sources")
[void]$sb.AppendLine("")
[void]$sb.AppendLine('```')
[void]$sb.AppendLine("Working/                                    [SOURCE DIRECTORY]")

foreach ($proj in $projects) {
    $relPath = $proj.FullName.Replace($script:RootDir + "\", "")
    [void]$sb.AppendLine("+-- $relPath")
}

[void]$sb.AppendLine('```')
[void]$sb.AppendLine("")
[void]$sb.AppendLine("---")
[void]$sb.AppendLine("")
[void]$sb.AppendLine("## Related Documentation")
[void]$sb.AppendLine("")
[void]$sb.AppendLine("- [[BUILD|Build System]]")
[void]$sb.AppendLine("- [[TESTING|Testing Guide]]")
[void]$sb.AppendLine("- [[test-post-audit|Post-Build Audit]]")
[void]$sb.AppendLine("")
[void]$sb.AppendLine("---")
[void]$sb.AppendLine("")
[void]$sb.AppendLine("*Generated by Test-PreBuild.ps1*")

$auditPath = Join-Path $auditDir "test-pre-audit.md"
Set-Content -Path $auditPath -Value $sb.ToString() -Encoding UTF8

if ($failed -gt 0) {
    Write-Host "  [PRE-BUILD] FAILED ($summary)" -ForegroundColor Red
} else {
    Write-Host "  [PRE-BUILD] PASSED ($summary)" -ForegroundColor Green
}

Write-Host ""
Write-Host "  Reports:" -ForegroundColor White
Write-Host "    - $auditPath" -ForegroundColor Gray
Write-Host "    - $script:LogPath" -ForegroundColor Gray
Write-Host ""

Stop-Transcript | Out-Null

if ($failed -gt 0) {
    exit 1
} else {
    exit 0
}
