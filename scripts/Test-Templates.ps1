<#
.SYNOPSIS
    Template Testing System for Alibre Design Extension
    Tests project and item templates outside of Visual Studio

.DESCRIPTION
    This script provides comprehensive testing for VS project/item templates by:
    1. Installing templates via dotnet new (NuGet package)
    2. Creating test projects from each template
    3. Building the generated projects
    4. Comparing generated output against source templates
    5. Validating file structure and content

.PARAMETER TestNuGet
    Test the NuGet/dotnet CLI templates

.PARAMETER TestVSIX
    Test the VSIX templates by extracting and simulating VS behavior

.PARAMETER OutputPath
    Directory for test output (default: docs\_test)

.PARAMETER Clean
    Remove test output before running

.PARAMETER Verbose
    Show detailed output

.EXAMPLE
    .\Test-Templates.ps1 -TestNuGet
    .\Test-Templates.ps1 -TestVSIX
    .\Test-Templates.ps1 -TestNuGet -TestVSIX -Clean
#>

param(
    [switch]$TestNuGet,
    [switch]$TestVSIX,
    [string]$OutputPath,
    [switch]$Clean,
    [switch]$Verbose
)

$ErrorActionPreference = "Stop"
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
$extensionFolder = Get-ConfigValue "extension.folderName" "VSExtensionForAlibreDesign"
$extensionPath = Join-Path $script:RootDir (Get-ConfigValue "paths.extension" "Extension")
$extensionFullPath = Join-Path $extensionPath $extensionFolder
$logDir = Join-Path $script:RootDir (Get-ConfigValue "paths.logs" "Docs/_logs")
$testPath = Get-ConfigValue "paths.test" "_test"
$script:AuditDir = Join-Path $script:RootDir (Get-ConfigValue "paths.audit" "Docs/_audit")

# Use config default if OutputPath not specified
if (-not $OutputPath) {
    $OutputPath = $testPath
}

# Start transcript logging
if (-not (Test-Path $logDir)) {
    New-Item -ItemType Directory -Path $logDir -Force | Out-Null
}
$timestamp = Get-Date -Format "yyyy-MM-dd_HH-mm-ss"
$script:LogPath = Join-Path $logDir "log-cli-test-post-$timestamp.txt"
Start-Transcript -Path $script:LogPath -Force | Out-Null

$script:TestDir = Join-Path $script:RootDir $OutputPath
$script:SourceDir = Join-Path $script:RootDir (Get-ConfigValue "paths.working" "Working/Projects")
$binDir = Join-Path $script:RootDir (Get-ConfigValue "paths.bin" "bin")
$script:NuGetPackage = Get-ChildItem -Path $binDir -Filter "*.nupkg" -ErrorAction SilentlyContinue |
                       Sort-Object LastWriteTime -Descending | Select-Object -First 1
$script:VSIXTemplatesDir = Join-Path $extensionFullPath "ProjectTemplates"
$script:NuGetPackageId = Get-ConfigValue "nuget.packageId" "AlibreDesign.Templates"

# Test results tracking
$script:TestResults = @{
    Passed = 0
    Failed = 0
    Warnings = 0
    Details = @()
}

# Audit data for detailed reporting
$script:AuditData = @{
    Timestamp = (Get-Date -Format "yyyy-MM-ddTHH:mm:ssZ")
    Version = "1.0.0"
    Summary = @{ Passed = 0; Failed = 0; Warnings = 0 }
    Templates = @()
}

# Template parameter simulation (mimics VS behavior)
# Note: Use actual VS template parameter format $param$ (no backticks)
$script:TemplateParams = @{
    '$safeprojectname$' = 'TestProject'
    '$projectname$' = 'TestProject'
    '$safeitemname$' = 'TestItem'
    '$itemname$' = 'TestItem'
    '$rootnamespace$' = 'TestProject'
    '$guid1$' = [guid]::NewGuid().ToString()
    '$guid2$' = [guid]::NewGuid().ToString()
    '$year$' = (Get-Date).Year.ToString()
    '$username$' = $env:USERNAME
    '$time$' = (Get-Date -Format "HH:mm:ss")
}

#region Console Output Functions
function Write-TestHeader {
    param([string]$Title)
    Write-Host ""
    Write-Host ("=" * 78) -ForegroundColor Cyan
    Write-Host "  $Title" -ForegroundColor White
    Write-Host ("=" * 78) -ForegroundColor Cyan
}

function Write-TestSection {
    param([string]$Title)
    Write-Host ""
    Write-Host "  [$Title]" -ForegroundColor Yellow
}

function Write-TestStep {
    param([string]$Message)
    Write-Host "    - $Message" -ForegroundColor Gray
}

function Write-TestPass {
    param([string]$Message)
    Write-Host "    [PASS] $Message" -ForegroundColor Green
    $script:TestResults.Passed++
}

function Write-TestFail {
    param([string]$Message, [string]$Details = "")
    Write-Host "    [FAIL] $Message" -ForegroundColor Red
    if ($Details) { Write-Host "           $Details" -ForegroundColor DarkRed }
    $script:TestResults.Failed++
    $script:TestResults.Details += @{ Test = $Message; Error = $Details }
}

function Write-TestWarn {
    param([string]$Message)
    Write-Host "    [WARN] $Message" -ForegroundColor Yellow
    $script:TestResults.Warnings++
}

function Write-TestInfo {
    param([string]$Message)
    if ($Verbose) { Write-Host "    [INFO] $Message" -ForegroundColor DarkGray }
}
#endregion

#region Utility Functions
function Initialize-TestEnvironment {
    Write-TestSection "Initializing Test Environment"

    if ($Clean -and (Test-Path $script:TestDir)) {
        Write-TestStep "Cleaning existing test directory..."
        Remove-Item $script:TestDir -Recurse -Force
    }

    if (-not (Test-Path $script:TestDir)) {
        New-Item -ItemType Directory -Path $script:TestDir -Force | Out-Null
    }

    Write-TestStep "Test directory: $script:TestDir"
}

function Compare-FileContent {
    param(
        [string]$SourceFile,
        [string]$GeneratedFile,
        [hashtable]$ParamReplacements = @{}
    )

    if (-not (Test-Path $SourceFile)) { return @{ Match = $false; Error = "Source file not found" } }
    if (-not (Test-Path $GeneratedFile)) { return @{ Match = $false; Error = "Generated file not found" } }

    $sourceContent = Get-Content $SourceFile -Raw
    $generatedContent = Get-Content $GeneratedFile -Raw

    # Apply parameter replacements to source for comparison
    foreach ($param in $ParamReplacements.Keys) {
        $sourceContent = $sourceContent -replace [regex]::Escape($param), $ParamReplacements[$param]
    }

    # Normalize line endings
    $sourceContent = $sourceContent -replace "`r`n", "`n"
    $generatedContent = $generatedContent -replace "`r`n", "`n"

    if ($sourceContent -eq $generatedContent) {
        return @{ Match = $true }
    } else {
        return @{ Match = $false; Error = "Content mismatch" }
    }
}

function Compare-DirectoryStructure {
    param(
        [string]$SourceDir,
        [string]$GeneratedDir,
        [string[]]$ExcludePatterns = @("bin", "obj", ".vs", "*.vstemplate", "*.user")
    )

    $results = @{
        MissingInGenerated = @()
        ExtraInGenerated = @()
        ContentMismatches = @()
    }

    # Get source files (excluding patterns)
    $sourceFiles = Get-ChildItem -Path $SourceDir -Recurse -File | Where-Object {
        $path = $_.FullName
        $exclude = $false
        foreach ($pattern in $ExcludePatterns) {
            if ($path -like "*$pattern*") { $exclude = $true; break }
        }
        -not $exclude
    } | ForEach-Object { $_.FullName.Substring($SourceDir.Length + 1) }

    # Get generated files
    $generatedFiles = Get-ChildItem -Path $GeneratedDir -Recurse -File -ErrorAction SilentlyContinue | Where-Object {
        $path = $_.FullName
        $exclude = $false
        foreach ($pattern in $ExcludePatterns) {
            if ($path -like "*$pattern*") { $exclude = $true; break }
        }
        -not $exclude
    } | ForEach-Object { $_.FullName.Substring($GeneratedDir.Length + 1) }

    # Find missing files
    foreach ($file in $sourceFiles) {
        # Account for renamed project files
        $matchFile = $file
        if ($file -match "\.(csproj|vbproj)$") {
            # Project files get renamed to $safeprojectname$
            $matchFile = $file -replace "^[^\\]+\.(csproj|vbproj)$", "TestProject.`$1"
        }

        $found = $generatedFiles | Where-Object {
            $_ -eq $file -or $_ -eq $matchFile -or
            ($_ -replace "^[^\\]+\.(csproj|vbproj)$", "") -eq ($file -replace "^[^\\]+\.(csproj|vbproj)$", "")
        }
        if (-not $found) {
            $results.MissingInGenerated += $file
        }
    }

    return $results
}

function Test-ProjectBuild {
    param([string]$ProjectPath)

    $projectFile = Get-ChildItem -Path $ProjectPath -Filter "*.csproj" -ErrorAction SilentlyContinue | Select-Object -First 1
    if (-not $projectFile) {
        $projectFile = Get-ChildItem -Path $ProjectPath -Filter "*.vbproj" -ErrorAction SilentlyContinue | Select-Object -First 1
    }
    if (-not $projectFile) {
        $projectFile = Get-ChildItem -Path $ProjectPath -Filter "*.fsproj" -ErrorAction SilentlyContinue | Select-Object -First 1
    }

    if (-not $projectFile) {
        return @{ Success = $false; Error = "No project file found" }
    }

    try {
        # Check if this is a legacy .NET Framework project (not SDK-style)
        $projContent = Get-Content $projectFile.FullName -Raw -ErrorAction SilentlyContinue
        $isLegacyProject = $projContent -notmatch '<Project\s+Sdk='

        if ($isLegacyProject) {
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

            if ($msbuildPath) {
                # Use MSBuild for legacy .NET Framework projects with PackageReference
                $output = & $msbuildPath $projectFile.FullName /t:Restore,Build /p:Configuration=Debug /nologo /v:q 2>&1
            } else {
                # Fallback to dotnet if MSBuild not found
                $output = & dotnet build $projectFile.FullName --nologo -v q 2>&1
            }
        } else {
            # Use dotnet build for SDK-style projects
            $output = & dotnet build $projectFile.FullName --nologo -v q 2>&1
        }

        if ($LASTEXITCODE -eq 0) {
            return @{ Success = $true }
        } else {
            return @{ Success = $false; Error = ($output | Out-String) }
        }
    } catch {
        return @{ Success = $false; Error = $_.Exception.Message }
    }
}
#endregion

#region NuGet Template Testing
function Test-NuGetTemplates {
    Write-TestHeader "TESTING NUGET/DOTNET CLI TEMPLATES"

    if (-not $script:NuGetPackage) {
        Write-TestFail "NuGet package not found in bin folder"
        Write-TestStep "Run Build-All.ps1 first to create the package"
        return
    }

    Write-TestSection "Installing Templates"
    Write-TestStep "Package: $($script:NuGetPackage.Name)"

    # Uninstall any existing version first
    Write-TestStep "Uninstalling existing templates..."
    & dotnet new uninstall $script:NuGetPackageId 2>&1 | Out-Null

    # Install from local package
    Write-TestStep "Installing from local package..."
    $installOutput = & dotnet new install $script:NuGetPackage.FullName 2>&1
    if ($LASTEXITCODE -ne 0) {
        Write-TestFail "Failed to install templates" ($installOutput | Out-String)
        return
    }
    Write-TestPass "Templates installed successfully"

    # List available templates
    Write-TestSection "Discovering Installed Templates"
    $templates = & dotnet new list alibre 2>&1
    Write-Host $templates

    # Test each template
    $nugetTestDir = Join-Path $script:TestDir "NuGet"
    if (-not (Test-Path $nugetTestDir)) {
        New-Item -ItemType Directory -Path $nugetTestDir -Force | Out-Null
    }

    # Define templates to test (short names from dotnet new)
    $templatesToTest = @(
        @{ ShortName = "alibre-script-cs"; DisplayName = "Alibre Script AddOn (C#)"; SourceFolder = "AlibreScriptAddonCS" }
        @{ ShortName = "alibre-script-vb"; DisplayName = "Alibre Script AddOn (VB)"; SourceFolder = "AlibreScriptAddonVB" }
        @{ ShortName = "alibre-addon-cs"; DisplayName = "Alibre Single File (C#)"; SourceFolder = "AlibreSingleFileAddonCS" }
        @{ ShortName = "alibre-addon-vb"; DisplayName = "Alibre Single File (VB)"; SourceFolder = "AlibreSingleFileAddonVB" }
        @{ ShortName = "alibre-ribbon-cs"; DisplayName = "Alibre Ribbon (C#)"; SourceFolder = "AlibreSingleFileAddonCSRibbon" }
        @{ ShortName = "alibre-ribbon-vb"; DisplayName = "Alibre Ribbon (VB)"; SourceFolder = "AlibreSingleFileAddonVBRibbon" }
    )

    foreach ($template in $templatesToTest) {
        Write-TestSection "Testing: $($template.DisplayName)"

        # Initialize audit entry for this template
        $templateAudit = @{
            Name = $template.DisplayName
            ShortName = $template.ShortName
            Type = "NuGet"
            SourceFolder = $template.SourceFolder
            Tests = @{
                Install = @{ Status = "pass" }  # Already passed at package level
                Create = @{ Status = "pending"; DurationMs = 0 }
                Build = @{ Status = "pending"; DurationMs = 0 }
            }
            Files = @{
                Source = @()
                Generated = @()
            }
        }

        $projectName = "Test_$($template.ShortName -replace '-', '_')"
        $projectDir = Join-Path $nugetTestDir $projectName

        # Clean existing
        if (Test-Path $projectDir) { Remove-Item $projectDir -Recurse -Force }

        # Create project
        Write-TestStep "Creating project with 'dotnet new $($template.ShortName)'..."
        $createStart = Get-Date
        $createOutput = & dotnet new $template.ShortName -n $projectName -o $projectDir 2>&1

        if ($LASTEXITCODE -ne 0) {
            Write-TestFail "Failed to create project" ($createOutput | Out-String)
            $templateAudit.Tests.Create.Status = "fail"
            $templateAudit.Tests.Create.Error = ($createOutput | Out-String)
            $script:AuditData.Templates += $templateAudit
            continue
        }
        Write-TestPass "Project created successfully"
        $templateAudit.Tests.Create.Status = "pass"
        $templateAudit.Tests.Create.DurationMs = ((Get-Date) - $createStart).TotalMilliseconds

        # Audit generated files
        $generatedFileObjects = Get-ChildItem -Path $projectDir -Recurse -File -ErrorAction SilentlyContinue |
                               Where-Object { $_.FullName -notlike "*\bin\*" -and $_.FullName -notlike "*\obj\*" }
        $templateAudit.Files.Generated = @($generatedFileObjects | ForEach-Object {
            @{
                Name = $_.Name
                Size = $_.Length
                Extension = $_.Extension
                RelativePath = $_.FullName.Substring($projectDir.Length + 1)
            }
        })

        # Verify file structure
        Write-TestStep "Verifying file structure..."
        $sourceFolder = Join-Path $script:SourceDir $template.SourceFolder
        if ($template.SourceFolder -like "*CS*" -and (Test-Path (Join-Path $sourceFolder "src"))) {
            $sourceFolder = Join-Path $sourceFolder "src"
        }

        # Audit source files for comparison
        if (Test-Path $sourceFolder) {
            $sourceFileObjects = Get-ChildItem -Path $sourceFolder -Recurse -File -ErrorAction SilentlyContinue |
                                Where-Object { $_.FullName -notlike "*\bin\*" -and $_.FullName -notlike "*\obj\*" }
            $templateAudit.Files.Source = @($sourceFileObjects | ForEach-Object {
                @{
                    Name = $_.Name
                    Size = $_.Length
                    Extension = $_.Extension
                    RelativePath = $_.FullName.Substring($sourceFolder.Length + 1)
                }
            })
        }

        $comparison = Compare-DirectoryStructure -SourceDir $sourceFolder -GeneratedDir $projectDir

        if ($comparison.MissingInGenerated.Count -gt 0) {
            Write-TestWarn "Missing files: $($comparison.MissingInGenerated -join ', ')"
        } else {
            Write-TestPass "All expected files present"
        }

        # Test build
        Write-TestStep "Building project..."
        $buildStart = Get-Date
        $buildResult = Test-ProjectBuild -ProjectPath $projectDir

        if ($buildResult.Success) {
            Write-TestPass "Project builds successfully"
            $templateAudit.Tests.Build.Status = "pass"
        } else {
            Write-TestFail "Build failed" $buildResult.Error
            $templateAudit.Tests.Build.Status = "fail"
            $templateAudit.Tests.Build.Error = $buildResult.Error
        }
        $templateAudit.Tests.Build.DurationMs = ((Get-Date) - $buildStart).TotalMilliseconds

        # Add completed audit to global tracking
        $script:AuditData.Templates += $templateAudit
    }

    # Cleanup - uninstall templates
    Write-TestSection "Cleanup"
    Write-TestStep "Uninstalling test templates..."
    & dotnet new uninstall $script:NuGetPackageId 2>&1 | Out-Null
    Write-TestPass "Templates uninstalled"
}
#endregion

#region VSIX Template Testing
function Test-VSIXTemplates {
    Write-TestHeader "TESTING VSIX PROJECT TEMPLATES"

    if (-not (Test-Path $script:VSIXTemplatesDir)) {
        Write-TestFail "VSIX templates directory not found: $script:VSIXTemplatesDir"
        return
    }

    $vsixTestDir = Join-Path $script:TestDir "VSIX"
    if (-not (Test-Path $vsixTestDir)) {
        New-Item -ItemType Directory -Path $vsixTestDir -Force | Out-Null
    }

    # Get all template ZIPs
    $templateZips = Get-ChildItem -Path $script:VSIXTemplatesDir -Filter "*.zip"

    foreach ($zip in $templateZips) {
        Write-TestSection "Testing: $($zip.BaseName)"

        # Initialize audit entry for this template
        $templateAudit = @{
            Name = $zip.BaseName
            Type = "VSIX"
            SourcePath = $zip.FullName
            Tests = @{
                Extraction = @{ Status = "pending"; DurationMs = 0 }
                Validation = @{ Status = "pending"; DurationMs = 0 }
                Generation = @{ Status = "pending"; FilesCreated = 0 }
                Build = @{ Status = "pending"; DurationMs = 0 }
            }
            Files = @{
                Source = @()
                Generated = @()
            }
        }

        $extractDir = Join-Path $vsixTestDir "$($zip.BaseName)_extracted"
        $projectDir = Join-Path $vsixTestDir "$($zip.BaseName)_project"

        # Clean existing
        if (Test-Path $extractDir) { Remove-Item $extractDir -Recurse -Force }
        if (Test-Path $projectDir) { Remove-Item $projectDir -Recurse -Force }

        # Extract template
        Write-TestStep "Extracting template ZIP..."
        $extractStart = Get-Date
        try {
            Expand-Archive -Path $zip.FullName -DestinationPath $extractDir -Force
            Write-TestPass "Template extracted"
            $templateAudit.Tests.Extraction.Status = "pass"
            $templateAudit.Tests.Extraction.DurationMs = ((Get-Date) - $extractStart).TotalMilliseconds

            # Audit source files
            $sourceFiles = Get-ChildItem -Path $extractDir -Recurse -File | Where-Object { $_.Extension -ne ".vstemplate" }
            $templateAudit.Files.Source = @($sourceFiles | ForEach-Object {
                @{
                    Name = $_.Name
                    Size = $_.Length
                    Extension = $_.Extension
                    RelativePath = $_.FullName.Substring($extractDir.Length + 1)
                }
            })
        } catch {
            Write-TestFail "Failed to extract template" $_.Exception.Message
            $templateAudit.Tests.Extraction.Status = "fail"
            $templateAudit.Tests.Extraction.Error = $_.Exception.Message
            $script:AuditData.Templates += $templateAudit
            continue
        }

        # Read and validate vstemplate
        Write-TestStep "Validating .vstemplate..."
        $validationStart = Get-Date
        $vstemplateFile = Get-ChildItem -Path $extractDir -Filter "*.vstemplate" | Select-Object -First 1
        if (-not $vstemplateFile) {
            Write-TestFail "No .vstemplate file found"
            $templateAudit.Tests.Validation.Status = "fail"
            $templateAudit.Tests.Validation.Error = "No .vstemplate file found"
            $script:AuditData.Templates += $templateAudit
            continue
        }

        try {
            [xml]$vstemplate = Get-Content $vstemplateFile.FullName
            $projectFile = $vstemplate.VSTemplate.TemplateContent.Project.File
            Write-TestPass ".vstemplate is valid XML"
            Write-TestInfo "Project file: $projectFile"
            $templateAudit.Tests.Validation.Status = "pass"
            $templateAudit.Tests.Validation.DurationMs = ((Get-Date) - $validationStart).TotalMilliseconds
        } catch {
            Write-TestFail "Invalid .vstemplate XML" $_.Exception.Message
            $templateAudit.Tests.Validation.Status = "fail"
            $templateAudit.Tests.Validation.Error = $_.Exception.Message
            $script:AuditData.Templates += $templateAudit
            continue
        }

        # Simulate VS project creation
        Write-TestStep "Simulating VS project creation..."
        New-Item -ItemType Directory -Path $projectDir -Force | Out-Null

        # Copy and transform files
        $templateFiles = Get-ChildItem -Path $extractDir -Recurse -File |
                        Where-Object { $_.Extension -ne ".vstemplate" }

        # Build a flat list of all ProjectItem elements (including those in Folder elements)
        $allProjectItems = @()
        $projectItems = $vstemplate.VSTemplate.TemplateContent.Project.ProjectItem
        if ($projectItems) { $allProjectItems += $projectItems }

        # Also get ProjectItems from Folder elements recursively
        $folders = $vstemplate.VSTemplate.TemplateContent.Project.Folder
        foreach ($folder in $folders) {
            if ($folder.ProjectItem) { $allProjectItems += $folder.ProjectItem }
        }

        foreach ($file in $templateFiles) {
            $relativePath = $file.FullName.Substring($extractDir.Length + 1)
            $destPath = Join-Path $projectDir $relativePath
            $destDir = Split-Path $destPath -Parent

            if (-not (Test-Path $destDir)) {
                New-Item -ItemType Directory -Path $destDir -Force | Out-Null
            }

            # Check if file needs parameter replacement (search all ProjectItems including those in folders)
            $replaceParams = $allProjectItems |
                            Where-Object { $_.InnerText -eq $file.Name -and $_.ReplaceParameters -eq "true" }

            if ($replaceParams -or $file.Extension -in @(".cs", ".vb", ".fs", ".csproj", ".vbproj", ".fsproj", ".adc", ".txt")) {
                # Read content and replace parameters
                $content = Get-Content $file.FullName -Raw
                foreach ($param in $script:TemplateParams.Keys) {
                    $content = $content -replace [regex]::Escape($param), $script:TemplateParams[$param]
                }

                # Rename project file
                if ($file.Name -eq $projectFile) {
                    $destPath = Join-Path $projectDir "TestProject$($file.Extension)"
                }

                Set-Content -Path $destPath -Value $content -Encoding UTF8
            } else {
                Copy-Item $file.FullName -Destination $destPath -Force
            }
        }
        Write-TestPass "Project files created with parameter substitution"

        # Verify file structure
        Write-TestStep "Verifying generated structure..."
        $generatedFileObjects = Get-ChildItem -Path $projectDir -Recurse -File
        $generatedFiles = $generatedFileObjects | ForEach-Object { $_.FullName.Substring($projectDir.Length + 1) }
        Write-TestInfo "Generated files: $($generatedFiles.Count)"

        # Audit generated files
        $templateAudit.Files.Generated = @($generatedFileObjects | ForEach-Object {
            @{
                Name = $_.Name
                Size = $_.Length
                Extension = $_.Extension
                RelativePath = $_.FullName.Substring($projectDir.Length + 1)
            }
        })

        if ($generatedFiles.Count -eq 0) {
            Write-TestFail "No files generated"
            $templateAudit.Tests.Generation.Status = "fail"
            $templateAudit.Tests.Generation.Error = "No files generated"
            $script:AuditData.Templates += $templateAudit
            continue
        }
        Write-TestPass "Files generated: $($generatedFiles.Count)"
        $templateAudit.Tests.Generation.Status = "pass"
        $templateAudit.Tests.Generation.FilesCreated = $generatedFiles.Count

        # Check if this is a template-only project (contains unreplaced $safeprojectname$)
        $projFile = Get-ChildItem $projectDir -Filter "*.csproj" -ErrorAction SilentlyContinue | Select-Object -First 1
        if (-not $projFile) {
            $projFile = Get-ChildItem $projectDir -Filter "*.vbproj" -ErrorAction SilentlyContinue | Select-Object -First 1
        }
        if (-not $projFile) {
            $projFile = Get-ChildItem $projectDir -Filter "*.fsproj" -ErrorAction SilentlyContinue | Select-Object -First 1
        }
        $projectFileContent = if ($projFile) { Get-Content $projFile.FullName -Raw -ErrorAction SilentlyContinue } else { "" }
        $isTemplateOnly = $projectFileContent -match '\$safeprojectname\$'

        if ($isTemplateOnly) {
            Write-TestWarn "Template-only project - skipping build (contains `$safeprojectname`$ placeholders)"
            $templateAudit.Tests.Build.Status = "skipped"
            $templateAudit.Tests.Build.Reason = "Template-only project with unreplaced parameters"
        } else {
            # Test build
            Write-TestStep "Building generated project..."
            $buildStart = Get-Date
            $buildResult = Test-ProjectBuild -ProjectPath $projectDir

            if ($buildResult.Success) {
                Write-TestPass "Project builds successfully"
                $templateAudit.Tests.Build.Status = "pass"
            } else {
                Write-TestFail "Build failed" $buildResult.Error
                $templateAudit.Tests.Build.Status = "fail"
                $templateAudit.Tests.Build.Error = $buildResult.Error
            }
            $templateAudit.Tests.Build.DurationMs = ((Get-Date) - $buildStart).TotalMilliseconds
        }

        # Add completed audit to global tracking
        $script:AuditData.Templates += $templateAudit
    }
}
#endregion

#region Report Generation
function Get-DirectoryAudit {
    param([string]$Path, [string]$BasePath = $Path)

    $audit = @{
        Path = $Path.Replace($BasePath, ".")
        Files = @()
        Folders = @()
        TotalFiles = 0
        TotalSize = 0
    }

    if (Test-Path $Path) {
        $items = Get-ChildItem -Path $Path -Force -ErrorAction SilentlyContinue

        foreach ($item in $items) {
            if ($item.PSIsContainer) {
                $audit.Folders += $item.Name
            } else {
                $audit.Files += @{
                    Name = $item.Name
                    Size = $item.Length
                    Extension = $item.Extension
                    Modified = $item.LastWriteTime.ToString("yyyy-MM-dd HH:mm:ss")
                }
                $audit.TotalSize += $item.Length
            }
        }
        $audit.TotalFiles = $audit.Files.Count
    }

    return $audit
}

function Archive-ExistingReports {
    <#
    .SYNOPSIS
        Archives existing report files to history folder with timestamps
    #>
    $historyDir = Join-Path $script:TestDir "history"

    # Create history directory if it doesn't exist
    if (-not (Test-Path $historyDir)) {
        New-Item -ItemType Directory -Path $historyDir -Force | Out-Null
    }

    # Archive existing report.md if it exists
    $reportPath = Join-Path $script:TestDir "report.md"
    if (Test-Path $reportPath) {
        $reportInfo = Get-Item $reportPath
        $timestamp = $reportInfo.LastWriteTime.ToString("yyyy-MM-dd_HHmmss")
        $archiveName = "report_$timestamp.md"
        $archivePath = Join-Path $historyDir $archiveName
        Move-Item -Path $reportPath -Destination $archivePath -Force
        Write-TestInfo "Archived previous report to history/$archiveName"
    }

    # Archive existing audit.json if it exists
    $auditPath = Join-Path $script:TestDir "audit.json"
    if (Test-Path $auditPath) {
        $auditInfo = Get-Item $auditPath
        $timestamp = $auditInfo.LastWriteTime.ToString("yyyy-MM-dd_HHmmss")
        $archiveName = "audit_$timestamp.json"
        $archivePath = Join-Path $historyDir $archiveName
        Move-Item -Path $auditPath -Destination $archivePath -Force
        Write-TestInfo "Archived previous audit to history/$archiveName"
    }

    # Cleanup old history files (keep last 10 of each type)
    $reportFiles = Get-ChildItem -Path $historyDir -Filter "report_*.md" -ErrorAction SilentlyContinue | Sort-Object LastWriteTime -Descending
    if ($reportFiles.Count -gt 10) {
        $reportFiles | Select-Object -Skip 10 | Remove-Item -Force
    }

    $auditFiles = Get-ChildItem -Path $historyDir -Filter "audit_*.json" -ErrorAction SilentlyContinue | Sort-Object LastWriteTime -Descending
    if ($auditFiles.Count -gt 10) {
        $auditFiles | Select-Object -Skip 10 | Remove-Item -Force
    }
}

function Export-AuditJson {
    # Update summary
    $script:AuditData.Summary.Passed = $script:TestResults.Passed
    $script:AuditData.Summary.Failed = $script:TestResults.Failed
    $script:AuditData.Summary.Warnings = $script:TestResults.Warnings

    $auditPath = Join-Path $script:TestDir "audit.json"
    $script:AuditData | ConvertTo-Json -Depth 10 | Set-Content -Path $auditPath -Encoding UTF8

    return $auditPath
}

function Export-MarkdownReport {
    $reportPath = Join-Path $script:TestDir "report.md"

    $totalTests = $script:TestResults.Passed + $script:TestResults.Failed + $script:TestResults.Warnings
    $timestamp = Get-Date -Format "yyyy-MM-dd HH:mm:ss"

    # Build report using StringBuilder for efficiency
    $sb = [System.Text.StringBuilder]::new()

    [void]$sb.AppendLine("# Template Test Report")
    [void]$sb.AppendLine("")
    [void]$sb.AppendLine("> Generated: $timestamp")
    [void]$sb.AppendLine("> Test Directory: ``$script:TestDir``")
    [void]$sb.AppendLine("")
    [void]$sb.AppendLine("## Summary")
    [void]$sb.AppendLine("")
    [void]$sb.AppendLine("| Metric | Count |")
    [void]$sb.AppendLine("|--------|-------|")
    [void]$sb.AppendLine("| **Total Tests** | $totalTests |")
    [void]$sb.AppendLine("| **Passed** | $($script:TestResults.Passed) |")
    [void]$sb.AppendLine("| **Failed** | $($script:TestResults.Failed) |")
    [void]$sb.AppendLine("| **Warnings** | $($script:TestResults.Warnings) |")
    [void]$sb.AppendLine("")
    [void]$sb.AppendLine("## Test Results by Template")
    [void]$sb.AppendLine("")

    # Group templates by type
    $vsixTemplates = $script:AuditData.Templates | Where-Object { $_.Type -eq "VSIX" }
    $nugetTemplates = $script:AuditData.Templates | Where-Object { $_.Type -eq "NuGet" }

    if ($vsixTemplates.Count -gt 0) {
        [void]$sb.AppendLine("### VSIX Templates")
        [void]$sb.AppendLine("")
        [void]$sb.AppendLine("| Template | Extraction | Validation | Generation | Build |")
        [void]$sb.AppendLine("|----------|------------|------------|------------|-------|")

        foreach ($t in $vsixTemplates) {
            $ext = if ($t.Tests.Extraction.Status -eq "pass") { "PASS" } else { "FAIL" }
            $val = if ($t.Tests.Validation.Status -eq "pass") { "PASS" } else { "FAIL" }
            $gen = if ($t.Tests.Generation.Status -eq "pass") { "PASS ($($t.Tests.Generation.FilesCreated) files)" } else { "FAIL" }
            $bld = switch ($t.Tests.Build.Status) {
                "pass" { "PASS" }
                "skipped" { "SKIPPED" }
                default { "FAIL" }
            }
            [void]$sb.AppendLine("| $($t.Name) | $ext | $val | $gen | $bld |")
        }
        [void]$sb.AppendLine("")
    }

    if ($nugetTemplates.Count -gt 0) {
        [void]$sb.AppendLine("### NuGet/dotnet CLI Templates")
        [void]$sb.AppendLine("")
        [void]$sb.AppendLine("| Template | Install | Create | Build |")
        [void]$sb.AppendLine("|----------|---------|--------|-------|")

        foreach ($t in $nugetTemplates) {
            $inst = if ($t.Tests.Install.Status -eq "pass") { "PASS" } else { "FAIL" }
            $crt = if ($t.Tests.Create.Status -eq "pass") { "PASS" } else { "FAIL" }
            $bld = if ($t.Tests.Build.Status -eq "pass") { "PASS" } else { "FAIL" }
            [void]$sb.AppendLine("| $($t.Name) | $inst | $crt | $bld |")
        }
        [void]$sb.AppendLine("")
    }

    # Failed tests details
    if ($script:TestResults.Failed -gt 0) {
        [void]$sb.AppendLine("## Failed Tests")
        [void]$sb.AppendLine("")

        foreach ($detail in $script:TestResults.Details) {
            [void]$sb.AppendLine("### $($detail.Test)")
            [void]$sb.AppendLine("")
            [void]$sb.AppendLine('```')
            [void]$sb.AppendLine($detail.Error)
            [void]$sb.AppendLine('```')
            [void]$sb.AppendLine("")
        }
    }

    # File audit section
    [void]$sb.AppendLine("## File Audit")
    [void]$sb.AppendLine("")
    [void]$sb.AppendLine("### Test Output Structure")
    [void]$sb.AppendLine("")
    [void]$sb.AppendLine('```')
    [void]$sb.AppendLine("$script:TestDir/")

    # Add directory tree
    if (Test-Path $script:TestDir) {
        $dirs = Get-ChildItem -Path $script:TestDir -Directory -Recurse | Sort-Object FullName
        foreach ($dir in $dirs) {
            $depth = ($dir.FullName.Replace($script:TestDir, "").Split([IO.Path]::DirectorySeparatorChar) | Where-Object { $_ }).Count
            $indent = "  " * $depth
            [void]$sb.AppendLine("${indent}+-- $($dir.Name)/")
        }
    }

    [void]$sb.AppendLine('```')
    [void]$sb.AppendLine("")
    [void]$sb.AppendLine("### Generated Projects")
    [void]$sb.AppendLine("")

    foreach ($t in $script:AuditData.Templates) {
        if ($t.Files.Generated.Count -gt 0) {
            [void]$sb.AppendLine("#### $($t.Name)")
            [void]$sb.AppendLine("")
            [void]$sb.AppendLine("| File | Size |")
            [void]$sb.AppendLine("|------|------|")

            foreach ($f in $t.Files.Generated) {
                $size = if ($f.Size -gt 1024) { "{0:N1} KB" -f ($f.Size / 1024) } else { "$($f.Size) B" }
                [void]$sb.AppendLine("| ``$($f.Name)`` | $size |")
            }
            [void]$sb.AppendLine("")
        }
    }

    # Related documentation links (Obsidian format)
    [void]$sb.AppendLine("## Related Documentation")
    [void]$sb.AppendLine("")
    [void]$sb.AppendLine("- [[BUILD|Build System]]")
    [void]$sb.AppendLine("- [[ARCHITECTURE|Architecture]]")
    [void]$sb.AppendLine("- [[TESTING|Testing Guide]]")
    [void]$sb.AppendLine("- [[CHANGELOG|Changelog]]")
    [void]$sb.AppendLine("")
    [void]$sb.AppendLine("---")
    [void]$sb.AppendLine("")
    [void]$sb.AppendLine("*Report generated by Test-Templates.ps1*")

    Set-Content -Path $reportPath -Value $sb.ToString() -Encoding UTF8
    return $reportPath
}

function Show-TestSummary {
    Write-Host ""
    Write-Host ("=" * 78) -ForegroundColor Cyan
    Write-Host "  TEST SUMMARY" -ForegroundColor White
    Write-Host ("=" * 78) -ForegroundColor Cyan
    Write-Host ""
    Write-Host "  Passed:   $($script:TestResults.Passed)" -ForegroundColor Green
    Write-Host "  Failed:   $($script:TestResults.Failed)" -ForegroundColor $(if ($script:TestResults.Failed -gt 0) { "Red" } else { "Gray" })
    Write-Host "  Warnings: $($script:TestResults.Warnings)" -ForegroundColor $(if ($script:TestResults.Warnings -gt 0) { "Yellow" } else { "Gray" })
    Write-Host ""

    if ($script:TestResults.Failed -gt 0) {
        Write-Host "  Failed Tests:" -ForegroundColor Red
        foreach ($detail in $script:TestResults.Details) {
            Write-Host "    - $($detail.Test)" -ForegroundColor Red
            if ($detail.Error) {
                $shortError = ($detail.Error -split "`n")[0]
                if ($shortError.Length -gt 60) { $shortError = $shortError.Substring(0, 60) + "..." }
                Write-Host "      $shortError" -ForegroundColor DarkRed
            }
        }
        Write-Host ""
    }

    # Archive existing reports before generating new ones
    Archive-ExistingReports

    # Generate reports
    Write-Host "  Generating reports..." -ForegroundColor Gray
    $auditPath = Export-AuditJson
    $reportPath = Export-MarkdownReport
    $auditMapPath = Export-TestAuditMap

    Write-Host ""
    Write-Host "  Reports:" -ForegroundColor White
    Write-Host "    - $reportPath" -ForegroundColor Gray
    Write-Host "    - $auditPath" -ForegroundColor Gray
    Write-Host "    - $auditMapPath" -ForegroundColor Gray
    Write-Host "    - $script:LogPath" -ForegroundColor Gray

    # Show history info
    $historyDir = Join-Path $script:TestDir "history"
    if (Test-Path $historyDir) {
        $historyCount = (Get-ChildItem -Path $historyDir -Filter "report_*.md" -ErrorAction SilentlyContinue).Count
        if ($historyCount -gt 0) {
            Write-Host "    - $historyCount previous report(s) in history/" -ForegroundColor DarkGray
        }
    }

    Write-Host ""
    Write-Host "  Test output: $script:TestDir" -ForegroundColor Gray
    Write-Host ""

    Stop-Transcript | Out-Null
}

function Export-TestAuditMap {
    # Use auditDir from config (set at script start as $script:AuditDir)
    if (-not (Test-Path $script:AuditDir)) {
        New-Item -ItemType Directory -Path $script:AuditDir -Force | Out-Null
    }

    $timestamp = Get-Date -Format "yyyy-MM-dd HH:mm:ss"
    $totalTests = $script:TestResults.Passed + $script:TestResults.Failed + $script:TestResults.Warnings

    $sb = [System.Text.StringBuilder]::new()

    [void]$sb.AppendLine("# Audit Map: test-post.cmd")
    [void]$sb.AppendLine("")
    [void]$sb.AppendLine("> Post-Build Template Validation")
    [void]$sb.AppendLine("> Generated: $timestamp")
    [void]$sb.AppendLine("")
    [void]$sb.AppendLine("## Script Chain")
    [void]$sb.AppendLine("")
    [void]$sb.AppendLine('```')
    [void]$sb.AppendLine("test-post.cmd")
    [void]$sb.AppendLine("    +-- Test-Templates.ps1 -TestVSIX")
    [void]$sb.AppendLine('```')
    [void]$sb.AppendLine("")
    [void]$sb.AppendLine("---")
    [void]$sb.AppendLine("")
    [void]$sb.AppendLine("## Results Summary")
    [void]$sb.AppendLine("")
    [void]$sb.AppendLine("| Metric | Value |")
    [void]$sb.AppendLine("|--------|-------|")
    [void]$sb.AppendLine("| Total Tests | $totalTests |")
    [void]$sb.AppendLine("| Passed | $($script:TestResults.Passed) |")
    [void]$sb.AppendLine("| Failed | $($script:TestResults.Failed) |")
    [void]$sb.AppendLine("| Warnings | $($script:TestResults.Warnings) |")
    [void]$sb.AppendLine("| Status | $(if ($script:TestResults.Failed -gt 0) { 'FAILED' } else { 'PASSED' }) |")
    [void]$sb.AppendLine("")
    [void]$sb.AppendLine("---")
    [void]$sb.AppendLine("")
    [void]$sb.AppendLine("## Input Sources")
    [void]$sb.AppendLine("")
    [void]$sb.AppendLine('```')
    $extRelPath = (Get-ConfigValue "paths.extension" "Extension") + "/" + (Get-ConfigValue "extension.folderName" "VSExtensionForAlibreDesign")
    [void]$sb.AppendLine("$extRelPath/ProjectTemplates/   [SOURCE]")

    $templateZips = Get-ChildItem -Path $script:VSIXTemplatesDir -Filter "*.zip" -ErrorAction SilentlyContinue
    foreach ($zip in $templateZips) {
        $size = "{0:N2} KB" -f ($zip.Length / 1024)
        [void]$sb.AppendLine("+-- $($zip.Name)  [$size]")
    }

    [void]$sb.AppendLine('```')
    [void]$sb.AppendLine("")
    [void]$sb.AppendLine("---")
    [void]$sb.AppendLine("")
    [void]$sb.AppendLine("## Output Structure")
    [void]$sb.AppendLine("")
    [void]$sb.AppendLine('```')
    [void]$sb.AppendLine("docs/_test/                                [OUTPUT]")
    [void]$sb.AppendLine("+-- report.md                              [TEST REPORT]")
    [void]$sb.AppendLine("+-- audit.json                             [AUDIT DATA]")
    [void]$sb.AppendLine("+-- history/                               [ARCHIVED]")
    [void]$sb.AppendLine("+-- VSIX/                                  [TEST WORKSPACE]")

    $vsixTestDir = Join-Path $script:TestDir "VSIX"
    if (Test-Path $vsixTestDir) {
        $testDirs = Get-ChildItem -Path $vsixTestDir -Directory | Sort-Object Name
        foreach ($dir in $testDirs) {
            [void]$sb.AppendLine("    +-- $($dir.Name)/")
        }
    }

    [void]$sb.AppendLine('```')
    [void]$sb.AppendLine("")
    [void]$sb.AppendLine("---")
    [void]$sb.AppendLine("")
    [void]$sb.AppendLine("## Template Test Results")
    [void]$sb.AppendLine("")
    [void]$sb.AppendLine("| Template | Extraction | Validation | Generation | Build |")
    [void]$sb.AppendLine("|----------|------------|------------|------------|-------|")

    foreach ($t in $script:AuditData.Templates | Where-Object { $_.Type -eq "VSIX" }) {
        $ext = if ($t.Tests.Extraction.Status -eq "pass") { "PASS" } else { "FAIL" }
        $val = if ($t.Tests.Validation.Status -eq "pass") { "PASS" } else { "FAIL" }
        $gen = if ($t.Tests.Generation.Status -eq "pass") { "PASS ($($t.Tests.Generation.FilesCreated))" } else { "FAIL" }
        $bld = switch ($t.Tests.Build.Status) {
            "pass" { "PASS" }
            "skipped" { "SKIP" }
            default { "FAIL" }
        }
        [void]$sb.AppendLine("| $($t.Name) | $ext | $val | $gen | $bld |")
    }

    [void]$sb.AppendLine("")
    [void]$sb.AppendLine("---")
    [void]$sb.AppendLine("")
    [void]$sb.AppendLine("## Generated Files by Template")
    [void]$sb.AppendLine("")

    foreach ($t in $script:AuditData.Templates | Where-Object { $_.Type -eq "VSIX" }) {
        [void]$sb.AppendLine("### $($t.Name)")
        [void]$sb.AppendLine("")
        [void]$sb.AppendLine("| File | Size | Extension |")
        [void]$sb.AppendLine("|------|------|-----------|")

        foreach ($f in $t.Files.Generated) {
            $size = if ($f.Size -gt 1024) { "{0:N1} KB" -f ($f.Size / 1024) } else { "$($f.Size) B" }
            [void]$sb.AppendLine("| ``$($f.Name)`` | $size | $($f.Extension) |")
        }
        [void]$sb.AppendLine("")
    }

    [void]$sb.AppendLine("---")
    [void]$sb.AppendLine("")
    [void]$sb.AppendLine("## Related Documentation")
    [void]$sb.AppendLine("")
    [void]$sb.AppendLine("- [[BUILD|Build System]]")
    [void]$sb.AppendLine("- [[TESTING|Testing Guide]]")
    [void]$sb.AppendLine("- [[test-pre-audit|Pre-Build Audit]]")
    [void]$sb.AppendLine("- [[build-audit|Build Audit]]")
    [void]$sb.AppendLine("")
    [void]$sb.AppendLine("---")
    [void]$sb.AppendLine("")
    [void]$sb.AppendLine("*Generated by Test-Templates.ps1*")

    $auditMapPath = Join-Path $script:AuditDir "test-post-audit.md"
    Set-Content -Path $auditMapPath -Value $sb.ToString() -Encoding UTF8
    return $auditMapPath
}
#endregion

# Main
Write-Host ""
Write-Host "================================================================================" -ForegroundColor Cyan
Write-Host "  ALIBRE DESIGN EXTENSION - TEMPLATE TEST SUITE" -ForegroundColor White
Write-Host "================================================================================" -ForegroundColor Cyan

Initialize-TestEnvironment

if (-not $TestNuGet -and -not $TestVSIX) {
    Write-Host ""
    Write-Host "  Usage: .\Test-Templates.ps1 [-TestNuGet] [-TestVSIX] [-Clean] [-Verbose]" -ForegroundColor Yellow
    Write-Host ""
    Write-Host "  Options:" -ForegroundColor Gray
    Write-Host "    -TestNuGet   Test dotnet CLI templates (requires bin/*.nupkg)" -ForegroundColor Gray
    Write-Host "    -TestVSIX    Test VSIX templates by simulating VS behavior" -ForegroundColor Gray
    Write-Host "    -Clean       Remove test output before running" -ForegroundColor Gray
    Write-Host "    -Verbose     Show detailed output" -ForegroundColor Gray
    Write-Host ""
    exit 0
}

if ($TestNuGet) {
    Test-NuGetTemplates
}

if ($TestVSIX) {
    Test-VSIXTemplates
}

Show-TestSummary

exit $script:TestResults.Failed
#endregion
