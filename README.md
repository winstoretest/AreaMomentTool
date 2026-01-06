# AreaMomentTool

An Alibre Design add-on that calculates Area Moments of Inertia for selected faces.

## Project Status

| Item | Status |
|------|--------|
| Build | GitHub Actions (Windows) |
| Signing | Local (Sectigo USB token) |
| Distribution | GitHub Pages |
| Microsoft Store | Pending submission |

## Features

- Calculate Area Moments of Inertia (Ix, Iy, Ixy)
- Calculate Section Modulus and Radius of Gyration
- Support for selected faces in Part workspace
- ImGui-based modern UI with DirectX 9 rendering

## Requirements

- Alibre Design 28.1+ (64-bit)
- Windows 10/11 x64

## Installation

Download and run the installer from:
- **GitHub Releases**: https://github.com/winstoretest/AreaMomentTool/releases
- **Direct Download (Signed)**: https://winstoretest.github.io/AreaMomentTool/AreaMomentTool-1.0.0-Setup.exe

## Build & Release Workflow

### Overview

```
┌─────────────────┐     ┌──────────────────┐     ┌─────────────────┐
│  Push tag v*    │────▶│  GitHub Actions  │────▶│ GitHub Releases │
│  (e.g. v1.0.0)  │     │  Build & Package │     │ (unsigned .exe) │
└─────────────────┘     └──────────────────┘     └─────────────────┘
                                                          │
                                                          ▼
┌─────────────────┐     ┌──────────────────┐     ┌─────────────────┐
│ Microsoft Store │◀────│  GitHub Pages    │◀────│ Sign-Release.ps1│
│   Submission    │     │  (signed .exe)   │     │ (local signing) │
└─────────────────┘     └─────────────────┘     └─────────────────┘
```

### 1. Automated Build (GitHub Actions)

**Trigger**: Push a version tag (e.g., `v1.0.0`)

```bash
git tag v1.0.0
git push origin v1.0.0
```

**Workflow** (`.github/workflows/release.yml`):
1. Checkout code
2. Build C++ solution (Release x64) with MSBuild
3. Compile Inno Setup installer
4. Upload to GitHub Releases (unsigned)

**Artifacts**:
- `AreaMomentTool-{version}-Setup.exe` (unsigned)

### 2. Code Signing (Local)

**Requires**: Sectigo USB hardware token

```powershell
cd D:\AreaMomentToolGit\scripts
.\Sign-Release.ps1 -Version "1.0.0" -CertificateThumbprint "YOUR_THUMBPRINT"
```

**Script actions**:
1. Downloads unsigned installer from GitHub Releases
2. Signs with hardware token certificate
3. Uploads signed installer to gh-pages branch
4. Serves via GitHub Pages

**Find your certificate thumbprint**:
```powershell
certutil -store My | findstr "Cert Hash"
```

### 3. Microsoft Store Submission

**Partner Center Configuration**:

| Field | Value |
|-------|-------|
| Package URL | `https://winstoretest.github.io/AreaMomentTool/AreaMomentTool-1.0.0-Setup.exe` |
| Architecture | x64 |
| App Type | EXE |
| Installer parameters | `/VERYSILENT /SUPPRESSMSGBOXES /NORESTART` |

## Project Structure

```
AreaMomentToolGit/
├── .github/
│   └── workflows/
│       └── release.yml          # GitHub Actions workflow
├── scripts/
│   ├── Sign-Release.ps1         # Local signing script
│   └── Build-Installers.ps1     # Build utilities
├── sdk/
│   ├── AlibreX_64.tlb           # Alibre SDK type library
│   └── AlibreAddOn_64.tlb       # Alibre Add-On type library
├── imgui/                       # ImGui library (DirectX 9)
├── Res/                         # Resources
├── AreaMomentTool.vcxproj       # Visual Studio project
├── AreaMomentTool.sln           # Solution file
├── AreaMomentTool.iss           # Inno Setup script
├── AreaMomentTool.adc           # Alibre add-on configuration
├── AreaMomentsCommand.cpp       # Main command implementation
├── AreaMomentsCalculator.cpp    # Calculation logic
├── ImGuiAreaMomentsWindow.cpp   # UI implementation
└── README.md
```

## Key URLs

| Purpose | URL |
|---------|-----|
| Repository | https://github.com/winstoretest/AreaMomentTool |
| Releases | https://github.com/winstoretest/AreaMomentTool/releases |
| Signed Installer | https://winstoretest.github.io/AreaMomentTool/AreaMomentTool-1.0.0-Setup.exe |
| Actions | https://github.com/winstoretest/AreaMomentTool/actions |
| Pages Settings | https://github.com/winstoretest/AreaMomentTool/settings/pages |

## Configuration Files

### Inno Setup (`AreaMomentTool.iss`)

Defines the Windows installer:
- Installs to `Program Files\Alibre Design Add-Ons\AreaMomentTool`
- Registers in Windows Registry for Alibre Design discovery
- Requires admin privileges

### Alibre Add-On Config (`AreaMomentTool.adc`)

```xml
<AlibreDesignAddOn specificationVersion="1" friendlyName="Area Moments of Inertia">
   <DLL loadedWhen="Startup" location="AreaMomentTool.dll"/>
   <Menu text="Area Moments"/>
   <Workspace type="Part"/>
</AlibreDesignAddOn>
```

## Release Checklist

- [ ] Update version in `AreaMomentTool.iss` (auto-updated by CI)
- [ ] Commit and push changes to main
- [ ] Create and push version tag: `git tag v1.0.1 && git push origin v1.0.1`
- [ ] Wait for GitHub Actions build to complete
- [ ] Run `Sign-Release.ps1` with USB token connected
- [ ] Verify signed installer at GitHub Pages URL
- [ ] Submit to Microsoft Store Partner Center

## Troubleshooting

### Build fails with missing AlibreX_64.tlb
The SDK type libraries must be in the `sdk/` folder. These are included in the repo.

### GitHub Pages returns 404
1. Check Settings → Pages → Source is set to "Deploy from branch: gh-pages"
2. Verify the file was pushed to gh-pages branch

### Signing fails
1. Ensure USB token is connected
2. Verify certificate thumbprint is correct
3. Check SafeNet/eToken software is running

### Microsoft Store rejects URL
- URL must be HTTPS
- URL must not redirect (GitHub Pages direct URLs work)
- Binary must not change after submission

## License

See [LICENSE](LICENSE) file.
