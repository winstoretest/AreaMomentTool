<#
.SYNOPSIS
    Builds installers for Alibre Design addons and standalone applications.

.DESCRIPTION
    This script discovers all built addon DLLs and EXE applications, generates
    Inno Setup (.iss) script files for each, and compiles them into installers.

    For DLL addons:
    - Installs to Program Files\Alibre Design Add-Ons\<AddonName>
    - Creates registry entry at HKLM\SOFTWARE\Alibre Design Add-Ons\<AddonName>
    - Copies the .adc configuration file

    For EXE applications:
    - Installs to Program Files\<AppName>
    - Creates Start Menu shortcuts
    - Optional desktop shortcut

.PARAMETER Configuration
    Build configuration: Debug or Release. Default is Release.

.PARAMETER Clean
    Remove all existing installers before building.

.PARAMETER GenerateOnly
    Only generate .iss files, don't compile installers.

.PARAMETER ProjectFilter
    Only build installers for projects matching this pattern.

.EXAMPLE
    .\Build-Installers.ps1

    Builds installers for all projects.

.EXAMPLE
    .\Build-Installers.ps1 -ProjectFilter "alibre-export*"

    Builds installer only for matching projects.

.NOTES
    Requires Inno Setup 6.x to be installed.
    Download from: https://jrsoftware.org/isdl.php
#>

[CmdletBinding()]
param(
    [ValidateSet("Debug", "Release")]
    [string]$Configuration = "Release",

    [switch]$Clean,
    [switch]$GenerateOnly,
    [string]$ProjectFilter = "*",

    # Code signing parameters
    [switch]$Sign,
    [string]$CertificateThumbprint,
    [string]$TimestampUrl
)

$ErrorActionPreference = "Stop"
$script:StartTime = Get-Date

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

# Paths
$script:Paths = @{
    Root            = $script:RootDir
    Projects        = Join-Path $script:RootDir (Get-ConfigValue "paths.working" "Working/Projects")
    Installers      = Join-Path $script:RootDir (Get-ConfigValue "paths.installers" "Installers")
    Bin             = Join-Path $script:RootDir (Get-ConfigValue "paths.bin" "bin")
    Logs            = Join-Path $script:RootDir (Get-ConfigValue "paths.logs" "Docs/_logs")
    Audit           = Join-Path $script:RootDir (Get-ConfigValue "paths.audit" "Docs/_audit")
}

# ==============================================================================
# TRANSCRIPT LOGGING
# ==============================================================================

# Ensure log directory exists
if (-not (Test-Path $script:Paths.Logs)) {
    New-Item -ItemType Directory -Path $script:Paths.Logs -Force | Out-Null
}

# Start transcript logging
$timestamp = Get-Date -Format "yyyy-MM-dd_HH-mm-ss"
$script:LogPath = Join-Path $script:Paths.Logs "log-installers-$timestamp.txt"
Start-Transcript -Path $script:LogPath -Force | Out-Null

# Product info
$script:Publisher = Get-ConfigValue "product.publisher" "Alibre Design Extensions"
$script:Author = Get-ConfigValue "product.author" "Unknown"
$script:ProjectUrl = Get-ConfigValue "product.projectUrl" ""

# Version
$script:VersionMajor = Get-ConfigValue "version.major" 1
$script:VersionMinor = Get-ConfigValue "version.minor" 0
$script:VersionPatch = Get-ConfigValue "version.patch" 0
$script:Version = "$script:VersionMajor.$script:VersionMinor.$script:VersionPatch"

# Alibre registry path
$script:AlibreRegistryPath = "SOFTWARE\Alibre Design Add-Ons"

# ==============================================================================
# CONSOLE OUTPUT
# ==============================================================================

function Write-Banner {
    $banner = @"

================================================================================
  ALIBRE DESIGN INSTALLER BUILDER
  Version: $script:Version
================================================================================
  Project Root: $script:RootDir
  Configuration: $Configuration
  Output: $($script:Paths.Installers)
  Log: $script:LogPath
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
# INNO SETUP DETECTION
# ==============================================================================

function Find-InnoSetup {
    $searchPaths = @(
        "C:\Program Files (x86)\Inno Setup 6\ISCC.exe",
        "C:\Program Files\Inno Setup 6\ISCC.exe",
        "C:\Program Files (x86)\Inno Setup 5\ISCC.exe",
        "C:\Program Files\Inno Setup 5\ISCC.exe"
    )

    foreach ($path in $searchPaths) {
        if (Test-Path $path) {
            return $path
        }
    }

    # Try PATH
    $iscc = Get-Command "ISCC.exe" -ErrorAction SilentlyContinue
    if ($iscc) {
        return $iscc.Path
    }

    return $null
}

# ==============================================================================
# CODE SIGNING (SafeNet/eToken)
# ==============================================================================

function Find-SignTool {
    # Try config paths first
    $configPaths = Get-ConfigValue "signing.signToolPaths" @()
    foreach ($path in $configPaths) {
        if (Test-Path $path) {
            return $path
        }
    }

    # Search Windows SDK paths dynamically
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

function Sign-InstallerFile {
    <#
    .SYNOPSIS
        Signs an executable using SignTool with a hardware token certificate.
    .PARAMETER FilePath
        Path to the file to sign.
    .PARAMETER SignToolPath
        Path to signtool.exe.
    .PARAMETER Thumbprint
        SHA1 thumbprint of the certificate on the token.
    .PARAMETER TimestampUrl
        URL of the timestamp server.
    .PARAMETER DigestAlgorithm
        Hash algorithm (sha256 recommended).
    #>
    param(
        [string]$FilePath,
        [string]$SignToolPath,
        [string]$Thumbprint,
        [string]$TimestampUrl = "http://timestamp.digicert.com",
        [string]$DigestAlgorithm = "sha256"
    )

    if (-not (Test-Path $FilePath)) {
        throw "File not found: $FilePath"
    }

    $fileName = Split-Path $FilePath -Leaf
    Write-SubStep "Signing $fileName..."

    # Build signtool arguments for SafeNet/eToken
    # /sha1 selects certificate by thumbprint (works with hardware tokens)
    # /fd specifies the file digest algorithm
    # /tr specifies RFC 3161 timestamp server
    # /td specifies timestamp digest algorithm
    $arguments = @(
        "sign",
        "/sha1", $Thumbprint,
        "/fd", $DigestAlgorithm,
        "/tr", $TimestampUrl,
        "/td", $DigestAlgorithm,
        "/v",
        "`"$FilePath`""
    )

    $argString = $arguments -join " "

    $psi = New-Object System.Diagnostics.ProcessStartInfo
    $psi.FileName = $SignToolPath
    $psi.Arguments = $argString
    $psi.UseShellExecute = $false
    $psi.RedirectStandardOutput = $true
    $psi.RedirectStandardError = $true
    $psi.CreateNoWindow = $true

    $process = New-Object System.Diagnostics.Process
    $process.StartInfo = $psi
    $process.Start() | Out-Null

    $stdout = $process.StandardOutput.ReadToEnd()
    $stderr = $process.StandardError.ReadToEnd()
    $process.WaitForExit()

    if ($process.ExitCode -eq 0) {
        Write-SubStep "Signed successfully"
        return @{ Success = $true; Output = $stdout }
    } else {
        $errorMsg = if ($stderr) { $stderr } else { $stdout }
        Write-SubStep "Signing failed: $errorMsg"
        return @{ Success = $false; Error = $errorMsg; ExitCode = $process.ExitCode }
    }
}

# ==============================================================================
# PROJECT DISCOVERY
# ==============================================================================

function Get-ProjectInfo {
    <#
    .SYNOPSIS
        Discovers all projects and their build outputs.
    #>

    Write-Step "Discovering projects..."

    $projects = @()

    $projectFiles = Get-ChildItem -Path $script:Paths.Projects -Recurse -Include "*.csproj", "*.vbproj", "*.fsproj" -File |
                    Where-Object { $_.FullName -notmatch "\\(bin|obj)\\" }

    foreach ($projectFile in $projectFiles) {
        $projectDir = $projectFile.DirectoryName
        $projectName = [System.IO.Path]::GetFileNameWithoutExtension($projectFile.Name)

        # Skip if doesn't match filter
        if ($projectName -notlike $ProjectFilter) { continue }

        # Read project file to determine output type
        $projContent = Get-Content $projectFile.FullName -Raw

        # Determine output type
        $outputType = "Library"  # Default for .NET projects
        if ($projContent -match '<OutputType>([^<]+)</OutputType>') {
            $outputType = $matches[1]
        }

        $isExe = $outputType -in @("Exe", "WinExe")
        $extension = if ($isExe) { ".exe" } else { ".dll" }

        # Find build output
        $binPath = Join-Path $projectDir "bin\$Configuration"

        # Check for target framework subdirectory
        $targetFramework = "net481"
        if ($projContent -match '<TargetFramework>([^<]+)</TargetFramework>') {
            $targetFramework = $matches[1]
        }

        $outputDir = Join-Path $binPath $targetFramework
        if (-not (Test-Path $outputDir)) {
            $outputDir = $binPath
        }

        $outputFile = Join-Path $outputDir "$projectName$extension"

        # Find .adc file (addon configuration)
        $adcFile = Get-ChildItem -Path $projectDir -Filter "*.adc" -ErrorAction SilentlyContinue |
                   Where-Object { $_.FullName -notmatch "\\bin\\" } |
                   Select-Object -First 1

        # Find icon file
        $iconFile = Get-ChildItem -Path $projectDir -Include "*.ico" -Recurse -ErrorAction SilentlyContinue |
                    Where-Object { $_.FullName -notmatch "\\bin\\" -and $_.FullName -notmatch "\\obj\\" } |
                    Select-Object -First 1

        # Parse .adc file for addon info
        $addonInfo = @{
            FriendlyName = $projectName
            Description = "$projectName - Alibre Design Add-On"
            Author = $script:Author
        }

        if ($adcFile) {
            try {
                [xml]$adcXml = Get-Content $adcFile.FullName
                $root = $adcXml.AlibreDesignAddOn
                if ($root.friendlyName) { $addonInfo.FriendlyName = $root.friendlyName }
                if ($root.Description) { $addonInfo.Description = $root.Description }
                if ($root.Author.name) { $addonInfo.Author = $root.Author.name }
            } catch { }
        }

        # Get folder name for relative path calculation
        $relativePath = $projectFile.FullName.Substring($script:Paths.Projects.Length + 1)
        $folderName = $relativePath.Split('\')[0]

        $project = @{
            Name            = $projectName
            FolderName      = $folderName
            ProjectFile     = $projectFile.FullName
            ProjectDir      = $projectDir
            OutputType      = $outputType
            IsExe           = $isExe
            Extension       = $extension
            OutputDir       = $outputDir
            OutputFile      = $outputFile
            AdcFile         = $adcFile
            IconFile        = $iconFile
            AddonInfo       = $addonInfo
            HasBuild        = (Test-Path $outputFile)
        }

        $projects += $project

        $typeLabel = if ($isExe) { "EXE" } else { "DLL" }
        $buildStatus = if ($project.HasBuild) { "" } else { " [NOT BUILT]" }
        Write-SubStep "$projectName ($typeLabel)$buildStatus"
    }

    Write-Success "Found $($projects.Count) projects"
    return $projects
}

# ==============================================================================
# ISS FILE GENERATION - DLL ADDON
# ==============================================================================

function New-DllAddonIss {
    param([hashtable]$Project)

    $appName = $Project.AddonInfo.FriendlyName
    $appVersion = $script:Version
    $publisher = $script:Publisher
    $projectUrl = $script:ProjectUrl
    $outputDir = $Project.OutputDir
    $iconPath = if ($Project.IconFile) { $Project.IconFile.FullName } else { "" }
    $adcPath = if ($Project.AdcFile) { $Project.AdcFile.FullName } else { "" }

    # Generate unique AppId based on project name
    # Note: Inno Setup requires {{ to escape curly braces
    $appId = "{{$([guid]::NewGuid().ToString().ToUpper())}"

    $issContent = @"
; Inno Setup Script for $appName
; Generated by Build-Installers.ps1
; Alibre Design Add-On Installer

#define MyAppName "$appName"
#define MyAppVersion "$appVersion"
#define MyAppPublisher "$publisher"
#define MyAppURL "$projectUrl"
#define MyOutputDir "$outputDir"

[Setup]
AppId=$appId
AppName={#MyAppName}
AppVersion={#MyAppVersion}
AppPublisher={#MyAppPublisher}
AppPublisherURL={#MyAppURL}
AppSupportURL={#MyAppURL}
AppUpdatesURL={#MyAppURL}
DefaultDirName={autopf}\Alibre Design Add-Ons\{#MyAppName}
DefaultGroupName=Alibre Design Add-Ons\{#MyAppName}
DisableProgramGroupPage=yes
OutputBaseFilename={#MyAppName}-{#MyAppVersion}-Setup
Compression=lzma2/max
SolidCompression=yes
WizardStyle=modern
PrivilegesRequired=admin
ArchitecturesAllowed=x64compatible
ArchitecturesInstallIn64BitMode=x64compatible
"@

    if ($iconPath -and (Test-Path $iconPath)) {
        $issContent += "`nSetupIconFile=$iconPath"
    }

    $issContent += @"


[Languages]
Name: "english"; MessagesFile: "compiler:Default.isl"

[Files]
; Main DLL and dependencies
Source: "{#MyOutputDir}\*"; DestDir: "{app}"; Flags: ignoreversion recursesubdirs createallsubdirs
"@

    if ($adcPath -and (Test-Path $adcPath)) {
        $issContent += @"

; ADC configuration file (if not already in output)
Source: "$adcPath"; DestDir: "{app}"; Flags: ignoreversion
"@
    }

    $issContent += @"


[Registry]
; Register addon with Alibre Design (string value on Add-Ons key, not a subkey)
Root: HKLM; Subkey: "$script:AlibreRegistryPath"; ValueType: string; ValueName: "{#MyAppName}"; ValueData: "{app}"; Flags: uninsdeletevalue

[Icons]
Name: "{group}\Uninstall {#MyAppName}"; Filename: "{uninstallexe}"

[Code]
function InitializeSetup(): Boolean;
begin
  Result := True;
  // Check if Alibre Design is installed (optional validation)
  if not RegKeyExists(HKEY_LOCAL_MACHINE, 'SOFTWARE\Alibre, Inc.\Alibre Design') then
  begin
    if MsgBox('Alibre Design does not appear to be installed. Continue anyway?', mbConfirmation, MB_YESNO) = IDNO then
    begin
      Result := False;
    end;
  end;
end;
"@

    return $issContent
}

# ==============================================================================
# ISS FILE GENERATION - EXE APPLICATION
# ==============================================================================

function New-ExeAppIss {
    param([hashtable]$Project)

    $appName = $Project.AddonInfo.FriendlyName
    $appVersion = $script:Version
    $publisher = $script:Publisher
    $projectUrl = $script:ProjectUrl
    $outputDir = $Project.OutputDir
    $exeName = "$($Project.Name).exe"
    $iconPath = if ($Project.IconFile) { $Project.IconFile.FullName } else { "" }

    # Generate unique AppId based on project name
    # Note: Inno Setup requires {{ to escape curly braces
    $appId = "{{$([guid]::NewGuid().ToString().ToUpper())}"

    $issContent = @"
; Inno Setup Script for $appName
; Generated by Build-Installers.ps1
; Standalone Application Installer

#define MyAppName "$appName"
#define MyAppVersion "$appVersion"
#define MyAppPublisher "$publisher"
#define MyAppURL "$projectUrl"
#define MyAppExeName "$exeName"
#define MyOutputDir "$outputDir"

[Setup]
AppId=$appId
AppName={#MyAppName}
AppVersion={#MyAppVersion}
AppPublisher={#MyAppPublisher}
AppPublisherURL={#MyAppURL}
AppSupportURL={#MyAppURL}
AppUpdatesURL={#MyAppURL}
DefaultDirName={autopf}\{#MyAppName}
DefaultGroupName={#MyAppName}
DisableProgramGroupPage=yes
OutputBaseFilename={#MyAppName}-{#MyAppVersion}-Setup
Compression=lzma2/max
SolidCompression=yes
WizardStyle=modern
PrivilegesRequired=admin
ArchitecturesAllowed=x64compatible
ArchitecturesInstallIn64BitMode=x64compatible
"@

    if ($iconPath -and (Test-Path $iconPath)) {
        $issContent += "`nSetupIconFile=$iconPath"
    }

    $issContent += @"


[Languages]
Name: "english"; MessagesFile: "compiler:Default.isl"

[Tasks]
Name: "desktopicon"; Description: "{cm:CreateDesktopIcon}"; GroupDescription: "{cm:AdditionalIcons}"; Flags: unchecked

[Files]
; Main EXE and dependencies
Source: "{#MyOutputDir}\*"; DestDir: "{app}"; Flags: ignoreversion recursesubdirs createallsubdirs

[Icons]
Name: "{group}\{#MyAppName}"; Filename: "{app}\{#MyAppExeName}"
Name: "{group}\Uninstall {#MyAppName}"; Filename: "{uninstallexe}"
Name: "{autodesktop}\{#MyAppName}"; Filename: "{app}\{#MyAppExeName}"; Tasks: desktopicon

[Run]
Filename: "{app}\{#MyAppExeName}"; Description: "{cm:LaunchProgram,{#StringChange(MyAppName, '&', '&&')}}"; Flags: nowait postinstall skipifsilent
"@

    return $issContent
}

# ==============================================================================
# BUILD INSTALLERS
# ==============================================================================

function Build-Installers {
    param(
        [array]$Projects,
        [string]$InnoSetupPath,
        [hashtable]$SigningConfig = $null
    )

    Write-Section "BUILDING INSTALLERS"

    # Ensure output directory exists
    if (-not (Test-Path $script:Paths.Installers)) {
        New-Item -ItemType Directory -Path $script:Paths.Installers -Force | Out-Null
    }

    $results = @()

    foreach ($project in $Projects) {
        if (-not $project.HasBuild) {
            Write-Info "Skipping $($project.Name) - not built"
            continue
        }

        Write-Step "Building installer: $($project.Name)"

        try {
            # Generate .iss file
            $issPath = Join-Path $project.ProjectDir "$($project.Name).iss"

            if ($project.IsExe) {
                $issContent = New-ExeAppIss -Project $project
            } else {
                $issContent = New-DllAddonIss -Project $project
            }

            Write-SubStep "Generating $($project.Name).iss"
            Set-Content -Path $issPath -Value $issContent -Encoding UTF8

            if ($GenerateOnly) {
                Write-Success "Generated: $issPath"
                $results += @{
                    Name = $project.Name
                    Type = if ($project.IsExe) { "EXE" } else { "DLL" }
                    IssPath = $issPath
                    Success = $true
                    GenerateOnly = $true
                }
                continue
            }

            # Compile with Inno Setup
            Write-SubStep "Compiling installer..."

            $outputPath = $script:Paths.Installers
            $arguments = @(
                "/O`"$outputPath`"",
                "`"$issPath`""
            )

            $process = Start-Process -FilePath $InnoSetupPath -ArgumentList $arguments -Wait -PassThru -NoNewWindow

            if ($process.ExitCode -eq 0) {
                # Use the FriendlyName for the installer filename (matches what ISS generates)
                $installerName = "$($project.AddonInfo.FriendlyName)-$script:Version-Setup.exe"
                $installerPath = Join-Path $outputPath $installerName

                if (Test-Path $installerPath) {
                    $installerInfo = Get-Item $installerPath
                    $sizeKB = [math]::Round($installerInfo.Length / 1KB, 2)

                    # Code signing
                    $signed = $false
                    $signError = $null
                    if ($SigningConfig -and $SigningConfig.Enabled) {
                        $signResult = Sign-InstallerFile `
                            -FilePath $installerPath `
                            -SignToolPath $SigningConfig.SignToolPath `
                            -Thumbprint $SigningConfig.Thumbprint `
                            -TimestampUrl $SigningConfig.TimestampUrl `
                            -DigestAlgorithm $SigningConfig.DigestAlgorithm

                        $signed = $signResult.Success
                        if (-not $signed) {
                            $signError = $signResult.Error
                        }
                    }

                    $statusMsg = "$installerName ($sizeKB KB)"
                    if ($SigningConfig -and $SigningConfig.Enabled) {
                        $statusMsg += if ($signed) { " [SIGNED]" } else { " [SIGN FAILED]" }
                    }
                    Write-Success $statusMsg

                    $results += @{
                        Name = $project.Name
                        Type = if ($project.IsExe) { "EXE" } else { "DLL" }
                        InstallerPath = $installerPath
                        SizeKB = $sizeKB
                        IssPath = $issPath
                        Success = $true
                        Signed = $signed
                        SignError = $signError
                    }
                } else {
                    Write-Failure "Installer file not found after compilation"
                    $results += @{
                        Name = $project.Name
                        Success = $false
                        Error = "Output file not found"
                    }
                }
            } else {
                Write-Failure "Inno Setup failed (exit code $($process.ExitCode))"
                $results += @{
                    Name = $project.Name
                    Success = $false
                    Error = "ISCC exit code $($process.ExitCode)"
                }
            }
        }
        catch {
            Write-Failure "Error: $_"
            $results += @{
                Name = $project.Name
                Success = $false
                Error = $_.Exception.Message
            }
        }
    }

    return $results
}

# ==============================================================================
# AUDIT REPORT GENERATION
# ==============================================================================

function Export-InstallerAuditMap {
    param(
        [array]$Projects,
        [array]$Results,
        [TimeSpan]$BuildTime
    )

    # Ensure audit directory exists
    if (-not (Test-Path $script:Paths.Audit)) {
        New-Item -ItemType Directory -Path $script:Paths.Audit -Force | Out-Null
    }

    $timestamp = Get-Date -Format "yyyy-MM-dd HH:mm:ss"

    $sb = [System.Text.StringBuilder]::new()
    [void]$sb.AppendLine("# Audit Map: Build-Installers.ps1")
    [void]$sb.AppendLine("")
    [void]$sb.AppendLine("> Installer Build System")
    [void]$sb.AppendLine("> Generated: $timestamp")
    [void]$sb.AppendLine("")

    # Script Chain
    [void]$sb.AppendLine("## Script Chain")
    [void]$sb.AppendLine("")
    [void]$sb.AppendLine('```')
    [void]$sb.AppendLine("build-full-with-installers.cmd")
    [void]$sb.AppendLine("    +-- build-full.cmd (VSIX + NuGet)")
    [void]$sb.AppendLine("    +-- Build-Installers.ps1")
    [void]$sb.AppendLine("            +-- [1] Project Discovery")
    [void]$sb.AppendLine("            +-- [2] ISS File Generation")
    [void]$sb.AppendLine("            +-- [3] Inno Setup Compilation")
    [void]$sb.AppendLine("            +-- [4] Installer Output")
    [void]$sb.AppendLine('```')
    [void]$sb.AppendLine("")
    [void]$sb.AppendLine("---")
    [void]$sb.AppendLine("")

    # Results Summary
    $successCount = ($Results | Where-Object { $_.Success }).Count
    $failCount = ($Results | Where-Object { -not $_.Success }).Count
    $dllCount = ($Results | Where-Object { $_.Success -and $_.Type -eq "DLL" }).Count
    $exeCount = ($Results | Where-Object { $_.Success -and $_.Type -eq "EXE" }).Count
    $signedCount = ($Results | Where-Object { $_.Signed -eq $true }).Count
    $overallStatus = if ($failCount -eq 0) { "SUCCESS" } else { "FAILED" }

    [void]$sb.AppendLine("## Results Summary")
    [void]$sb.AppendLine("")
    [void]$sb.AppendLine("| Metric | Value |")
    [void]$sb.AppendLine("|--------|-------|")
    [void]$sb.AppendLine("| Total Projects | $($Projects.Count) |")
    [void]$sb.AppendLine("| Installers Built | $successCount |")
    [void]$sb.AppendLine("| DLL Add-Ons | $dllCount |")
    [void]$sb.AppendLine("| EXE Applications | $exeCount |")
    [void]$sb.AppendLine("| Signed | $signedCount |")
    [void]$sb.AppendLine("| Failed | $failCount |")
    [void]$sb.AppendLine("| Build Time | $($BuildTime.TotalSeconds.ToString('0.0'))s |")
    [void]$sb.AppendLine("| Status | $overallStatus |")
    [void]$sb.AppendLine("")
    [void]$sb.AppendLine("---")
    [void]$sb.AppendLine("")

    # Input Projects
    [void]$sb.AppendLine("## Input Projects")
    [void]$sb.AppendLine("")
    [void]$sb.AppendLine("| Project | Type | Build Status |")
    [void]$sb.AppendLine("|---------|------|--------------|")
    foreach ($project in $Projects) {
        $type = if ($project.IsExe) { "EXE" } else { "DLL" }
        $status = if ($project.HasBuild) { "Built" } else { "Not Built" }
        [void]$sb.AppendLine("| $($project.Name) | $type | $status |")
    }
    [void]$sb.AppendLine("")
    [void]$sb.AppendLine("---")
    [void]$sb.AppendLine("")

    # Build Results
    [void]$sb.AppendLine("## Build Results")
    [void]$sb.AppendLine("")
    [void]$sb.AppendLine("### Installers")
    [void]$sb.AppendLine("")
    [void]$sb.AppendLine("| Installer | Type | Size | Status | Signed |")
    [void]$sb.AppendLine("|-----------|------|------|--------|--------|")
    foreach ($result in $Results) {
        $status = if ($result.Success) { "PASS" } else { "FAIL" }
        $size = if ($result.SizeKB) { "$($result.SizeKB) KB" } else { "-" }
        $type = if ($result.Type) { $result.Type } else { "-" }
        $signed = if ($result.Signed -eq $true) { "Yes" } elseif ($result.Signed -eq $false) { "No" } else { "-" }
        [void]$sb.AppendLine("| $($result.Name) | $type | $size | $status | $signed |")
    }
    [void]$sb.AppendLine("")
    [void]$sb.AppendLine("---")
    [void]$sb.AppendLine("")

    # Output Structure
    [void]$sb.AppendLine("## Output Structure")
    [void]$sb.AppendLine("")
    [void]$sb.AppendLine('```')
    [void]$sb.AppendLine("Installers/                                 [OUTPUT DIRECTORY]")
    foreach ($result in ($Results | Where-Object { $_.Success -and -not $_.GenerateOnly })) {
        $fileName = "$($result.Name)-$script:Version-Setup.exe"
        $size = if ($result.SizeKB) { "[$($result.SizeKB) KB]" } else { "" }
        [void]$sb.AppendLine("+-- $fileName  $size")
    }
    [void]$sb.AppendLine('```')
    [void]$sb.AppendLine("")
    [void]$sb.AppendLine("---")
    [void]$sb.AppendLine("")

    # Registry Keys
    [void]$sb.AppendLine("## Registry Configuration")
    [void]$sb.AppendLine("")
    [void]$sb.AppendLine("DLL Add-Ons are registered at:")
    [void]$sb.AppendLine('```')
    [void]$sb.AppendLine("HKLM\$script:AlibreRegistryPath\<AddonName>")
    [void]$sb.AppendLine("    Path = <Installation Directory>")
    [void]$sb.AppendLine('```')
    [void]$sb.AppendLine("")
    [void]$sb.AppendLine("---")
    [void]$sb.AppendLine("")
    [void]$sb.AppendLine("## Related Documentation")
    [void]$sb.AppendLine("")
    [void]$sb.AppendLine("- [[build-audit|Build System Audit]]")
    [void]$sb.AppendLine("- [[BUILD|Build System]]")
    [void]$sb.AppendLine("")
    [void]$sb.AppendLine("---")
    [void]$sb.AppendLine("")
    [void]$sb.AppendLine("*Generated by Build-Installers.ps1*")

    $auditPath = Join-Path $script:Paths.Audit "installers-audit.md"
    Set-Content -Path $auditPath -Value $sb.ToString() -Encoding UTF8
    Write-Info "Audit: $auditPath"
}

# ==============================================================================
# MAIN EXECUTION
# ==============================================================================

try {
    Write-Banner

    # Find Inno Setup
    if (-not $GenerateOnly) {
        $innoSetup = Find-InnoSetup
        if (-not $innoSetup) {
            throw "Inno Setup not found. Please install from https://jrsoftware.org/isdl.php"
        }
        Write-Info "Inno Setup: $innoSetup"
    }

    # Set up code signing configuration
    $signingConfig = $null
    $doSign = $Sign -or (Get-ConfigValue "signing.enabled" $false)

    if ($doSign) {
        $signTool = Find-SignTool
        if (-not $signTool) {
            Write-Failure "SignTool not found. Install Windows SDK or specify path in build.config.json"
            throw "SignTool not found"
        }

        # Get thumbprint from parameter or config
        $thumbprint = if ($CertificateThumbprint) { $CertificateThumbprint } else { Get-ConfigValue "signing.certificateThumbprint" "" }
        if (-not $thumbprint) {
            throw "Certificate thumbprint required for signing. Use -CertificateThumbprint or set in build.config.json"
        }

        # Get timestamp URL from parameter or config
        $tsUrl = if ($TimestampUrl) { $TimestampUrl } else { Get-ConfigValue "signing.timestampUrl" "http://timestamp.digicert.com" }
        $digestAlg = Get-ConfigValue "signing.digestAlgorithm" "sha256"

        $signingConfig = @{
            Enabled = $true
            SignToolPath = $signTool
            Thumbprint = $thumbprint
            TimestampUrl = $tsUrl
            DigestAlgorithm = $digestAlg
        }

        Write-Info "SignTool: $signTool"
        Write-Info "Certificate: $($thumbprint.Substring(0, 8))..."
        Write-Info "Timestamp: $tsUrl"
    }

    # Clean if requested
    if ($Clean -and (Test-Path $script:Paths.Installers)) {
        Write-Step "Cleaning installers directory..."
        Get-ChildItem -Path $script:Paths.Installers -Filter "*.exe" | Remove-Item -Force
        Write-Success "Cleaned"
    }

    # Discover projects
    Write-Section "PROJECT DISCOVERY"
    $projects = Get-ProjectInfo

    if ($projects.Count -eq 0) {
        Write-Info "No projects found matching filter: $ProjectFilter"
        exit 0
    }

    $builtProjects = $projects | Where-Object { $_.HasBuild }
    if ($builtProjects.Count -eq 0) {
        throw "No built projects found. Run build-full.cmd first."
    }

    # Build installers
    $results = Build-Installers -Projects $projects -InnoSetupPath $innoSetup -SigningConfig $signingConfig

    # Summary
    $elapsed = (Get-Date) - $script:StartTime

    # Generate audit report
    Export-InstallerAuditMap -Projects $projects -Results $results -BuildTime $elapsed

    Write-Host ""
    Write-Host ("=" * 78) -ForegroundColor Green
    Write-Host "  INSTALLER BUILD COMPLETE" -ForegroundColor Green
    Write-Host ("=" * 78) -ForegroundColor Green
    Write-Host ""

    $successCount = ($results | Where-Object { $_.Success }).Count
    $failCount = ($results | Where-Object { -not $_.Success }).Count
    $signedCount = ($results | Where-Object { $_.Signed -eq $true }).Count

    $resultMsg = "  Results: $successCount succeeded, $failCount failed"
    if ($signingConfig -and $signingConfig.Enabled) {
        $resultMsg += ", $signedCount signed"
    }
    Write-Host $resultMsg -ForegroundColor White
    Write-Host ""

    $dllResults = $results | Where-Object { $_.Success -and $_.Type -eq "DLL" }
    $exeResults = $results | Where-Object { $_.Success -and $_.Type -eq "EXE" }

    if ($dllResults.Count -gt 0) {
        Write-Host "  DLL Add-On Installers:" -ForegroundColor Cyan
        foreach ($r in $dllResults) {
            if ($r.GenerateOnly) {
                Write-Host "    - $($r.Name).iss (generated)" -ForegroundColor Gray
            } else {
                $signStatus = if ($r.Signed) { " [Signed]" } else { "" }
                Write-Host "    - $($r.Name)-$script:Version-Setup.exe ($($r.SizeKB) KB)$signStatus" -ForegroundColor Gray
            }
        }
        Write-Host ""
    }

    if ($exeResults.Count -gt 0) {
        Write-Host "  EXE Application Installers:" -ForegroundColor Cyan
        foreach ($r in $exeResults) {
            if ($r.GenerateOnly) {
                Write-Host "    - $($r.Name).iss (generated)" -ForegroundColor Gray
            } else {
                $signStatus = if ($r.Signed) { " [Signed]" } else { "" }
                Write-Host "    - $($r.Name)-$script:Version-Setup.exe ($($r.SizeKB) KB)$signStatus" -ForegroundColor Gray
            }
        }
        Write-Host ""
    }

    if ($failCount -gt 0) {
        Write-Host "  Failed:" -ForegroundColor Red
        foreach ($r in ($results | Where-Object { -not $_.Success })) {
            Write-Host "    - $($r.Name): $($r.Error)" -ForegroundColor Red
        }
        Write-Host ""
    }

    Write-Host "  Output Directory: $($script:Paths.Installers)" -ForegroundColor White
    Write-Host "  Build Time: $($elapsed.TotalSeconds.ToString('0.0')) seconds" -ForegroundColor DarkGray
    Write-Host ""
    Write-Host "  Reports:" -ForegroundColor White
    Write-Host "    - $(Join-Path $script:Paths.Audit 'installers-audit.md')" -ForegroundColor Gray
    Write-Host "    - $script:LogPath" -ForegroundColor Gray
    Write-Host ""

    Stop-Transcript | Out-Null

    if ($failCount -gt 0) {
        exit 1
    }
}
catch {
    Write-Host ""
    Write-Host "BUILD FAILED: $_" -ForegroundColor Red
    Write-Host $_.ScriptStackTrace -ForegroundColor DarkRed
    Stop-Transcript | Out-Null
    exit 1
}
