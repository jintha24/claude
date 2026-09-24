; The Thief of London: Windows installer (Inno Setup 6, https://jrsoftware.org/isinfo.php)
;
; Build the game first (tools\build_windows.bat does both steps), then compile this with
; the Inno Setup Compiler, or from the command line:
;   "C:\Program Files (x86)\Inno Setup 6\ISCC.exe" installer\thief_of_london.iss
; The installer is written to installer\Output\TheThiefOfLondon-<version>-Setup.exe.
; The version can be given on the command line: ISCC /DAppVersion=0.12.0 ...

#ifndef AppVersion
  #define AppVersion "0.11.0"
#endif
#define AppName "The Thief of London"
#define AppPublisher "The Thief of London developers"
#define AppExeName "TheThiefOfLondon.exe"
#define AppPck "TheThiefOfLondon.pck"
#define BuildDir "..\builds\windows"

[Setup]
; AppId identifies the game to Windows (upgrades and uninstalling). Never change it.
AppId={{8F3B8E2A-6C1D-4B7E-9A51-3D0C7E1F2A64}
AppName={#AppName}
AppVersion={#AppVersion}
AppVerName={#AppName} {#AppVersion}
AppPublisher={#AppPublisher}
DefaultDirName={autopf}\{#AppName}
DefaultGroupName={#AppName}
DisableProgramGroupPage=yes
LicenseFile=LICENSE.txt
InfoAfterFile=README.txt
OutputDir=Output
OutputBaseFilename=TheThiefOfLondon-{#AppVersion}-Setup
SetupIconFile=..\assets\icon\thief_of_london.ico
UninstallDisplayIcon={app}\{#AppExeName}
UninstallDisplayName={#AppName}
Compression=lzma2/ultra64
SolidCompression=yes
LZMAUseSeparateProcess=yes
WizardStyle=modern
; 64-bit Windows 10 or 11 only (the game needs Vulkan or Direct3D 12).
ArchitecturesAllowed=x64compatible
ArchitecturesInstallIn64BitMode=x64compatible
MinVersion=10.0
; Installs for the current user without asking for admin rights; the player can choose
; "all users" instead.
PrivilegesRequired=lowest
PrivilegesRequiredOverridesAllowed=dialog
VersionInfoVersion={#AppVersion}.0
VersionInfoProductName={#AppName}
VersionInfoDescription={#AppName} Setup
CloseApplications=yes

[Languages]
Name: "english"; MessagesFile: "compiler:Default.isl"

[Tasks]
Name: "desktopicon"; Description: "{cm:CreateDesktopIcon}"; GroupDescription: "{cm:AdditionalIcons}"

[Files]
Source: "{#BuildDir}\{#AppExeName}"; DestDir: "{app}"; Flags: ignoreversion
Source: "{#BuildDir}\{#AppPck}"; DestDir: "{app}"; Flags: ignoreversion
; The console launcher shows errors in a terminal (useful if the game won't start).
Source: "{#BuildDir}\TheThiefOfLondon.console.exe"; DestDir: "{app}"; Flags: ignoreversion skipifsourcedoesntexist
Source: "README.txt"; DestDir: "{app}"; DestName: "Read Me.txt"; Flags: ignoreversion isreadme
Source: "LICENSE.txt"; DestDir: "{app}"; DestName: "Licence.txt"; Flags: ignoreversion
Source: "THIRD_PARTY_NOTICES.txt"; DestDir: "{app}"; DestName: "Third-party notices.txt"; Flags: ignoreversion

[Icons]
Name: "{autoprograms}\{#AppName}"; Filename: "{app}\{#AppExeName}"
Name: "{autoprograms}\{#AppName} (safe mode, Direct3D 12)"; Filename: "{app}\{#AppExeName}"; Parameters: "--rendering-driver d3d12"
Name: "{autodesktop}\{#AppName}"; Filename: "{app}\{#AppExeName}"; Tasks: desktopicon

[Run]
Filename: "{app}\{#AppExeName}"; Description: "{cm:LaunchProgram,{#StringChange(AppName, '&', '&&')}}"; Flags: nowait postinstall skipifsilent

[Code]
// Saved games and settings live in %APPDATA%\ThiefOfLondon. Uninstalling asks before
// deleting them (they're kept by default, so reinstalling carries on where you were).
procedure CurUninstallStepChanged(CurUninstallStep: TUninstallStep);
var
  SaveDir: String;
begin
  if CurUninstallStep = usPostUninstall then
  begin
    SaveDir := ExpandConstant('{userappdata}\ThiefOfLondon');
    if DirExists(SaveDir) then
      if MsgBox('Also delete your saved games and settings?' #13#10 + SaveDir, mbConfirmation, MB_YESNO or MB_DEFBUTTON2) = IDYES then
        DelTree(SaveDir, True, True, True);
  end;
end;
