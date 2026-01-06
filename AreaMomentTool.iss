; Inno Setup Script for AreaMomentTool
; Alibre Design Add-On Installer

#define MyAppName "AreaMomentTool"
#define MyAppVersion "1.0.0"
#define MyAppPublisher "winstoretest"
#define MyAppURL "https://github.com/winstoretest/AreaMomentTool"

[Setup]
AppId={{A1B2C3D4-E5F6-7890-ABCD-EF1234567890}
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

[Languages]
Name: "english"; MessagesFile: "compiler:Default.isl"

[Files]
; Main DLL from Release build
Source: "x64\Release\AreaMomentTool.dll"; DestDir: "{app}"; Flags: ignoreversion
; ADC configuration file
Source: "AreaMomentTool.adc"; DestDir: "{app}"; Flags: ignoreversion
; Icon file
Source: "AreaMomentTool.ico"; DestDir: "{app}"; Flags: ignoreversion

[Registry]
; Register addon with Alibre Design (string value on Add-Ons key, not a subkey)
Root: HKLM; Subkey: "SOFTWARE\Alibre Design Add-Ons"; ValueType: string; ValueName: "{#MyAppName}"; ValueData: "{app}"; Flags: uninsdeletevalue

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
