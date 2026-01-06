# Alibre Extensions Build Automation Scripts

This folder contains PowerShell scripts that automate the build, packaging, and deployment of Alibre Design Visual Studio templates.

## Quick Start

```powershell
# Navigate to Scripts directory
cd Scripts

# Build everything (templates + VSIX + NuGet)
.\Build-Templates.ps1 -Clean -BuildVSIX -BuildNuGet

# Test the VSIX in VS experimental instance
.\Install-VSIX.ps1 -Experimental -Launch

# Test the CLI templates
.\Build-DotnetTemplates.ps1 -TestInstall
```

## Scripts Overview

| Script | Purpose | Usage |
|--------|---------|-------|
| `Build-Templates.ps1` | Master build orchestrator | Main entry point for all builds |
| `New-VSTemplate.ps1` | Generates .vstemplate files | Called by Build-Templates |
| `New-TemplateZip.ps1` | Creates ZIP packages | Called by Build-Templates |
| `Build-DotnetTemplates.ps1` | Builds NuGet package for CLI | Standalone or via Build-Templates |
| `New-AlibreTemplate.ps1` | Interactive template creator | Add new templates from existing projects |
| `Install-VSIX.ps1` | Installs VSIX for testing | Test extensions in VS |

## Detailed Script Documentation

### Build-Templates.ps1

The master build script that coordinates all template packaging operations.

```powershell
# Basic build - just packages templates
.\Build-Templates.ps1

# Full clean build
.\Build-Templates.ps1 -Clean -BuildVSIX -BuildNuGet

# Build specific templates only
.\Build-Templates.ps1 -TemplateFilter "*VB*"

# Debug build
.\Build-Templates.ps1 -BuildVSIX -Configuration Debug
```

**Parameters:**
- `-Clean` - Remove existing packages before building
- `-BuildVSIX` - Build the Visual Studio extension package
- `-BuildNuGet` - Build the NuGet package for CLI templates
- `-Configuration` - Debug or Release (default: Release)
- `-TemplateFilter` - Build only matching templates (supports wildcards)

**What it does:**
1. Validates the build environment
2. Copies source files from `Working/` to staging
3. Generates `.vstemplate` files for VSIX
4. Creates ZIP packages in `Extension/.../ProjectTemplates/`
5. Optionally builds VSIX extension
6. Optionally builds NuGet package

---

### New-VSTemplate.ps1

Generates Visual Studio `.vstemplate` XML files from source projects.

```powershell
.\New-VSTemplate.ps1 -SourcePath "C:\staging\MyTemplate" `
                     -TemplateName "My Alibre AddOn" `
                     -Description "Description here" `
                     -Language "CSharp" `
                     -DefaultName "MyAddon" `
                     -SortOrder 150 `
                     -TemplateID "MyAlibreAddon"
```

**Parameters:**
- `-SourcePath` - Directory containing template files
- `-TemplateName` - Display name in VS New Project dialog
- `-Description` - Template description
- `-Language` - "CSharp" or "VisualBasic"
- `-DefaultName` - Default project name suggestion
- `-SortOrder` - Order in template list (lower = higher)
- `-TemplateID` - Unique identifier

**Template Parameters:**
The script configures these VS template parameters for replacement:
- `$safeprojectname$` - Safe project name (valid identifier)
- `$projectname$` - Original project name
- `$guid1$` - `$guid10$` - Generated GUIDs
- `$year$` - Current year
- `$username$` - Windows username

---

### New-TemplateZip.ps1

Creates ZIP packages from template source directories.

```powershell
.\New-TemplateZip.ps1 -SourcePath "C:\staging\MyTemplate" `
                      -OutputPath "C:\output\MyTemplate.zip" `
                      -Force
```

**Parameters:**
- `-SourcePath` - Directory with template files
- `-OutputPath` - Output ZIP file path
- `-ExcludePatterns` - Array of patterns to exclude
- `-Force` - Overwrite existing ZIP
- `-Detailed` - Show verbose progress

**Default Exclusions:**
- `bin`, `obj` - Build outputs
- `.vs`, `.git` - IDE/VCS folders
- `*.user`, `*.suo` - User settings
- `packages`, `node_modules` - Dependencies

---

### Build-DotnetTemplates.ps1

Builds the NuGet package for `dotnet new` CLI templates.

```powershell
# Basic build
.\Build-DotnetTemplates.ps1

# Build and test locally
.\Build-DotnetTemplates.ps1 -TestInstall

# Build specific version
.\Build-DotnetTemplates.ps1 -Version "1.1.0" -Clean
```

**Parameters:**
- `-OutputPath` - Directory for .nupkg output
- `-Version` - Package version (overrides nuspec)
- `-TestInstall` - Test installation after building
- `-Clean` - Remove existing packages first

**Output:**
Creates `Alibre.Templates.x.x.x.nupkg` in `Templates/dotnet/packages/`

**Publishing to NuGet.org:**
```powershell
nuget push Alibre.Templates.1.0.0.nupkg -Source https://api.nuget.org/v3/index.json -ApiKey YOUR_KEY
```

---

### New-AlibreTemplate.ps1

Interactive wizard for creating new templates from existing projects.

```powershell
# Interactive mode (recommended)
.\New-AlibreTemplate.ps1

# Automated mode
.\New-AlibreTemplate.ps1 -SourcePath "C:\MyProject" `
                         -TemplateName "My Custom AddOn (C#)" `
                         -Language "CSharp" `
                         -TemplateType "SingleFile"
```

**What it does:**
1. Copies source project to `Working/` directory
2. Cleans build artifacts
3. Adds template parameter placeholders
4. Creates CLI template configuration
5. Shows instructions for updating Build-Templates.ps1

**Template Types:**
- `SingleFile` - Basic menu-based AddOn
- `SingleFileRibbon` - AddOn with ribbon UI
- `Script` - AddOn with IronPython support

---

### Install-VSIX.ps1

Installs the VSIX extension for testing in Visual Studio.

```powershell
# Install to experimental instance (safe testing)
.\Install-VSIX.ps1 -Experimental

# Install and launch VS
.\Install-VSIX.ps1 -Experimental -Launch

# Install to normal VS instance
.\Install-VSIX.ps1

# Uninstall only
.\Install-VSIX.ps1 -Uninstall

# Specify VS version
.\Install-VSIX.ps1 -VSVersion "2026" -Experimental
```

**Parameters:**
- `-VSIXPath` - Path to VSIX file (auto-detected if omitted)
- `-Experimental` - Install to VS experimental instance
- `-VSVersion` - Target "2022" or "2026"
- `-Uninstall` - Remove extension instead of installing
- `-Launch` - Launch VS after installation

**VS Instances:**
- **Normal**: Your everyday VS installation
- **Experimental**: Isolated testing environment (recommended for development)

---

## Common Workflows

### Daily Development

```powershell
# 1. Make changes to templates in Working/ folder

# 2. Build and test
.\Build-Templates.ps1 -BuildVSIX
.\Install-VSIX.ps1 -Experimental -Launch

# 3. In VS: File > New > Project > search "Alibre"
```

### Adding a New Template

```powershell
# 1. Run the wizard
.\New-AlibreTemplate.ps1

# 2. Follow prompts to configure the template

# 3. Add the generated definition to Build-Templates.ps1

# 4. Build everything
.\Build-Templates.ps1 -Clean -BuildVSIX -BuildNuGet
```

### Preparing for Release

```powershell
# 1. Update version numbers
#    - source.extension.vsixmanifest
#    - Alibre.Templates.nuspec

# 2. Clean build everything
.\Build-Templates.ps1 -Clean -BuildVSIX -BuildNuGet -Configuration Release

# 3. Test installation
.\Install-VSIX.ps1 -Experimental -Launch
.\Build-DotnetTemplates.ps1 -TestInstall

# 4. Verify all templates work

# 5. Outputs:
#    - VSIX: Extension/VSExtensionForAlibreVB/bin/Release/VSExtensionForAlibreVB.vsix
#    - NuGet: Templates/dotnet/packages/Alibre.Templates.x.x.x.nupkg
```

### Publishing

**Visual Studio Marketplace:**
1. Go to https://marketplace.visualstudio.com/manage
2. Upload the VSIX file
3. Fill in marketplace details
4. Submit for review

**NuGet.org:**
```powershell
nuget push Templates\dotnet\packages\Alibre.Templates.1.0.0.nupkg `
    -Source https://api.nuget.org/v3/index.json `
    -ApiKey YOUR_API_KEY
```

---

## Directory Structure

```
AlibreExtensions/
├── Scripts/                      # <-- You are here
│   ├── Build-Templates.ps1       # Master build script
│   ├── New-VSTemplate.ps1        # .vstemplate generator
│   ├── New-TemplateZip.ps1       # ZIP packager
│   ├── Build-DotnetTemplates.ps1 # NuGet builder
│   ├── New-AlibreTemplate.ps1    # Template wizard
│   ├── Install-VSIX.ps1          # VSIX installer
│   └── README.md                 # This file
├── Working/                      # Template source projects
│   ├── AlibreScriptAddonCS/
│   ├── AlibreScriptAddonVB/
│   ├── AlibreSingleFileAddonCS/
│   └── ...
├── Extension/                    # VSIX project
│   └── VSExtensionForAlibreVB/
│       ├── ProjectTemplates/     # Template ZIPs go here
│       └── bin/                  # Built VSIX output
└── Templates/                    # CLI templates
    └── dotnet/
        ├── [template folders]
        ├── Alibre.Templates.nuspec
        └── packages/             # Built NuGet packages
```

---

## Troubleshooting

### Build fails with "MSBuild not found"
- Install Visual Studio 2022 or 2026
- Ensure VS includes the "VSIX development" workload

### VSIX won't install
- Close all Visual Studio windows first
- Check Windows Event Log for errors
- Try installing to experimental instance first

### Templates don't appear in VS
- Verify VSIX is installed: Extensions > Manage Extensions
- Clear VS template cache: `devenv /updateconfiguration`
- Check for errors in VS ActivityLog.xml

### NuGet package fails to build
- Ensure nuget.exe is available (script downloads automatically)
- Check that template.json files are valid JSON
- Verify nuspec file syntax

### CLI templates not found after install
- Run `dotnet new list alibre` to verify
- Check `~/.templateengine/` for installed templates
- Try uninstalling and reinstalling: `dotnet new uninstall Alibre.Templates`

---

## Getting Help

```powershell
# View detailed help for any script
Get-Help .\Build-Templates.ps1 -Full
Get-Help .\Install-VSIX.ps1 -Examples
```

---

## Version History

### 1.0.0 (December 2025)
- Initial release
- 6 scripts for complete build automation
- Support for VS 2022 and VS 2026
- Both VSIX and NuGet package building
- Interactive template creation wizard
