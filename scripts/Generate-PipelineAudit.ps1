<#
.SYNOPSIS
    Generates the build-full-audit.md from individual script audits.

.DESCRIPTION
    Aggregates data from test-pre-audit.md, build-audit.md, and test-post-audit.md
    to create a comprehensive pipeline audit.
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
$logDir = Join-Path $script:RootDir (Get-ConfigValue "paths.logs" "Docs/_logs")
$auditDir = Join-Path $script:RootDir (Get-ConfigValue "paths.audit" "Docs/_audit")
$testDir = Join-Path $script:RootDir (Get-ConfigValue "paths.test" "_test")
$binDir = Join-Path $script:RootDir (Get-ConfigValue "paths.bin" "bin")

# Start transcript logging
if (-not (Test-Path $logDir)) {
    New-Item -ItemType Directory -Path $logDir -Force | Out-Null
}
$timestamp = Get-Date -Format "yyyy-MM-dd_HH-mm-ss"
$script:LogPath = Join-Path $logDir "log-cli-pipeline-$timestamp.txt"
Start-Transcript -Path $script:LogPath -Force | Out-Null

# Parse pre-build audit for stats
$prePassed = 0
$preSkipped = 0
$preFailed = 0
$preAuditPath = Join-Path $auditDir "test-pre-audit.md"
if (Test-Path $preAuditPath) {
    $preContent = Get-Content $preAuditPath -Raw
    if ($preContent -match 'Passed \| (\d+)') { $prePassed = [int]$matches[1] }
    if ($preContent -match 'Skipped.*\| (\d+)') { $preSkipped = [int]$matches[1] }
    if ($preContent -match 'Failed \| (\d+)') { $preFailed = [int]$matches[1] }
}

# Parse build audit for stats
$projectZips = 0
$itemZips = 0
$vsixBuilt = $false
$nupkgBuilt = $false
$buildAuditPath = Join-Path $auditDir "build-audit.md"
if (Test-Path $buildAuditPath) {
    $buildContent = Get-Content $buildAuditPath -Raw
    if ($buildContent -match 'Project Templates \| (\d+) built') { $projectZips = [int]$matches[1] }
    if ($buildContent -match 'Item Templates \| (\d+) built') { $itemZips = [int]$matches[1] }
    $vsixBuilt = $buildContent -match 'VSIX \| BUILT'
    $nupkgBuilt = $buildContent -match 'NuGet \| BUILT'
}

# Parse post-build audit or audit.json for stats
$postPassed = 0
$postFailed = 0
$postWarnings = 0
$auditJsonPath = Join-Path $testDir "audit.json"
if (Test-Path $auditJsonPath) {
    $auditJson = Get-Content $auditJsonPath -Raw | ConvertFrom-Json
    $postPassed = $auditJson.summary.passed
    $postFailed = $auditJson.summary.failed
    $postWarnings = $auditJson.summary.warnings
} else {
    $postAuditPath = Join-Path $auditDir "test-post-audit.md"
    if (Test-Path $postAuditPath) {
        $postContent = Get-Content $postAuditPath -Raw
        if ($postContent -match 'Passed \| (\d+)') { $postPassed = [int]$matches[1] }
        if ($postContent -match 'Failed \| (\d+)') { $postFailed = [int]$matches[1] }
        if ($postContent -match 'Warnings \| (\d+)') { $postWarnings = [int]$matches[1] }
    }
}

# Determine overall status
$status = "SUCCESS"
if ($preFailed -gt 0 -or $postFailed -gt 0) { $status = "FAILED" }

$timestamp = Get-Date -Format "yyyy-MM-dd HH:mm:ss"

$sb = [System.Text.StringBuilder]::new()
[void]$sb.AppendLine("# Audit Map: build-full.cmd")
[void]$sb.AppendLine("")
[void]$sb.AppendLine("> Full Build Pipeline (Pre-Build + Build + Post-Build)")
[void]$sb.AppendLine("> Generated: $timestamp")
[void]$sb.AppendLine("")
[void]$sb.AppendLine("## Pipeline Overview")
[void]$sb.AppendLine("")
[void]$sb.AppendLine('```')
[void]$sb.AppendLine("build-full.cmd")
[void]$sb.AppendLine("    +-- test-pre.cmd --> Test-PreBuild.ps1")
[void]$sb.AppendLine("    +-- build.cmd    --> Build-All.ps1")
[void]$sb.AppendLine("    +-- test-post.cmd --> Test-Templates.ps1")
[void]$sb.AppendLine('```')
[void]$sb.AppendLine("")
[void]$sb.AppendLine("---")
[void]$sb.AppendLine("")

# Results Summary
[void]$sb.AppendLine("## Results Summary")
[void]$sb.AppendLine("")
[void]$sb.AppendLine("| Step | Metric | Value |")
[void]$sb.AppendLine("|------|--------|-------|")
[void]$sb.AppendLine("| Pre-Build | Passed | $prePassed |")
[void]$sb.AppendLine("| Pre-Build | Skipped | $preSkipped |")
[void]$sb.AppendLine("| Pre-Build | Failed | $preFailed |")
[void]$sb.AppendLine("| Build | Project Templates | $projectZips |")
[void]$sb.AppendLine("| Build | Item Templates | $itemZips |")
$vsixStr = if ($vsixBuilt) { "YES" } else { "NO" }
$nupkgStr = if ($nupkgBuilt) { "YES" } else { "NO" }
[void]$sb.AppendLine("| Build | VSIX Created | $vsixStr |")
[void]$sb.AppendLine("| Build | NuGet Created | $nupkgStr |")
[void]$sb.AppendLine("| Post-Build | Passed | $postPassed |")
[void]$sb.AppendLine("| Post-Build | Warnings | $postWarnings |")
[void]$sb.AppendLine("| Post-Build | Failed | $postFailed |")
[void]$sb.AppendLine("| **Pipeline** | **Status** | **$status** |")
[void]$sb.AppendLine("")
[void]$sb.AppendLine("---")
[void]$sb.AppendLine("")

# Pipeline Flow
[void]$sb.AppendLine("## Pipeline Flow")
[void]$sb.AppendLine("")
[void]$sb.AppendLine('```')
[void]$sb.AppendLine("STEP 1: Pre-Build Validation")
[void]$sb.AppendLine("  Input:  Working/*/*.csproj, Working/*/*.vbproj")
[void]$sb.AppendLine("  Action: dotnet build (verify source compiles)")
[void]$sb.AppendLine("  Result: $prePassed passed, $preSkipped skipped, $preFailed failed")
[void]$sb.AppendLine("")
[void]$sb.AppendLine("STEP 2: Build")
[void]$sb.AppendLine("  Input:  Working/*/, WorkingItems/*/")
[void]$sb.AppendLine("  Action: Package templates, MSBuild VSIX, NuGet pack")
[void]$sb.AppendLine("  Result: $projectZips project ZIPs, $itemZips item ZIPs")
[void]$sb.AppendLine("")
[void]$sb.AppendLine("STEP 3: Post-Build Testing")
[void]$sb.AppendLine("  Input:  Extension/.../ProjectTemplates/*.zip")
[void]$sb.AppendLine("  Action: Extract, simulate VS, verify builds")
[void]$sb.AppendLine("  Result: $postPassed passed, $postWarnings warnings, $postFailed failed")
[void]$sb.AppendLine('```')
[void]$sb.AppendLine("")
[void]$sb.AppendLine("---")
[void]$sb.AppendLine("")

# Final Outputs
[void]$sb.AppendLine("## Final Outputs")
[void]$sb.AppendLine("")
[void]$sb.AppendLine('```')
[void]$sb.AppendLine("$(Get-ConfigValue 'paths.bin' 'bin')/")

if (Test-Path $binDir) {
    $vsixFile = Get-ChildItem -Path $binDir -Filter "*.vsix" -ErrorAction SilentlyContinue | Select-Object -First 1
    if ($vsixFile) {
        $vsixSizeKB = [math]::Round($vsixFile.Length / 1KB, 2)
        [void]$sb.AppendLine("+-- $($vsixFile.Name)  [$vsixSizeKB KB]")
    }
    $nupkgFile = Get-ChildItem -Path $binDir -Filter "*.nupkg" -ErrorAction SilentlyContinue | Sort-Object LastWriteTime -Descending | Select-Object -First 1
    if ($nupkgFile) {
        $nupkgSizeKB = [math]::Round($nupkgFile.Length / 1KB, 2)
        [void]$sb.AppendLine("+-- $($nupkgFile.Name)  [$nupkgSizeKB KB]")
    }
}

[void]$sb.AppendLine("")
$testRelPath = Get-ConfigValue "paths.test" "_test"
[void]$sb.AppendLine("$testRelPath/")
[void]$sb.AppendLine("+-- report.md")
[void]$sb.AppendLine("+-- audit.json")
[void]$sb.AppendLine("+-- history/")
[void]$sb.AppendLine('```')
[void]$sb.AppendLine("")
[void]$sb.AppendLine("---")
[void]$sb.AppendLine("")

# Individual Audits
[void]$sb.AppendLine("## Individual Audit Reports")
[void]$sb.AppendLine("")
[void]$sb.AppendLine("| Script | Audit File | Status |")
[void]$sb.AppendLine("|--------|------------|--------|")

$preStatus = if ($preFailed -eq 0) { "PASSED" } else { "FAILED" }
$buildStatus = if ($vsixBuilt) { "PASSED" } else { "FAILED" }
$postStatus = if ($postFailed -eq 0) { "PASSED" } else { "FAILED" }

[void]$sb.AppendLine("| test-pre.cmd | [[test-pre-audit]] | $preStatus |")
[void]$sb.AppendLine("| build.cmd | [[build-audit]] | $buildStatus |")
[void]$sb.AppendLine("| test-post.cmd | [[test-post-audit]] | $postStatus |")
[void]$sb.AppendLine("")
[void]$sb.AppendLine("---")
[void]$sb.AppendLine("")
[void]$sb.AppendLine("## Related Documentation")
[void]$sb.AppendLine("")
[void]$sb.AppendLine("- [[BUILD|Build System]]")
[void]$sb.AppendLine("- [[TESTING|Testing Guide]]")
[void]$sb.AppendLine("- [[ARCHITECTURE|Architecture]]")
[void]$sb.AppendLine("")
[void]$sb.AppendLine("---")
[void]$sb.AppendLine("")
[void]$sb.AppendLine("*Generated by Generate-PipelineAudit.ps1*")

$auditPath = Join-Path $auditDir "build-full-audit.md"
Set-Content -Path $auditPath -Value $sb.ToString() -Encoding UTF8

Write-Host ""
Write-Host "  Pipeline Reports:" -ForegroundColor White
Write-Host "    - $auditPath" -ForegroundColor Gray
Write-Host "    - $(Join-Path $auditDir 'test-pre-audit.md')" -ForegroundColor Gray
Write-Host "    - $(Join-Path $auditDir 'build-audit.md')" -ForegroundColor Gray
Write-Host "    - $(Join-Path $auditDir 'test-post-audit.md')" -ForegroundColor Gray
Write-Host "    - $(Join-Path $testDir 'report.md')" -ForegroundColor Gray
Write-Host "    - $(Join-Path $testDir 'audit.json')" -ForegroundColor Gray
Write-Host "    - $script:LogPath" -ForegroundColor Gray
Write-Host ""

Stop-Transcript | Out-Null
