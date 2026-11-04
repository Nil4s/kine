; C78: Kine installer (Inno Setup 6). Built by tools/build_installer.sh, which passes /DAppVersion=, /DDistDir=, /DRepoDir=, /DOutDir=.
; Per-user by default (no admin, {localappdata}\Programs\Kine); the wizard offers "all users" via the standard dialog.
; User data lives in %APPDATA%\Godot\app_userdata\... (Godot's user dir): nothing here ever deletes it.
#ifndef AppVersion
  #define AppVersion "0.0.0"
#endif
#ifndef DistDir
  #error DistDir is required
#endif
#ifndef RepoDir
  #error RepoDir is required
#endif
#ifndef OutDir
  #define OutDir "."
#endif

[Setup]
AppId={{8D1C6B52-7A3E-4C0A-9F51-4B1E0C780001}
AppName=Kine
AppVersion={#AppVersion}
AppVerName=Kine {#AppVersion}
AppPublisher=Teschima Studios
DefaultDirName={autopf}\Kine
DefaultGroupName=Kine
DisableProgramGroupPage=yes
PrivilegesRequired=lowest
PrivilegesRequiredOverridesAllowed=dialog
LicenseFile={#DistDir}\LICENSE.txt
InfoBeforeFile={#DistDir}\THIRD_PARTY_NOTICES.txt
SetupIconFile={#RepoDir}\assets\brand\kine.ico
UninstallDisplayIcon={app}\Kine.exe
OutputDir={#OutDir}
OutputBaseFilename=Kine-Setup-{#AppVersion}
Compression=lzma2/max
SolidCompression=yes
WizardStyle=modern
ArchitecturesAllowed=x64compatible
ArchitecturesInstallIn64BitMode=x64compatible
CloseApplications=yes

[Languages]
Name: "english"; MessagesFile: "compiler:Default.isl"

[Tasks]
Name: "desktopicon"; Description: "Create a &desktop shortcut"; GroupDescription: "Shortcuts:"; Flags: unchecked

[Files]
Source: "{#DistDir}\Kine.exe"; DestDir: "{app}"; Flags: ignoreversion
Source: "{#DistDir}\Kine.console.exe"; DestDir: "{app}"; Flags: ignoreversion
Source: "{#DistDir}\*.dll"; DestDir: "{app}"; Flags: ignoreversion
Source: "{#DistDir}\LICENSE.txt"; DestDir: "{app}"; Flags: ignoreversion
Source: "{#DistDir}\THIRD_PARTY_NOTICES.txt"; DestDir: "{app}"; Flags: ignoreversion
Source: "{#DistDir}\licences\*"; DestDir: "{app}\licences"; Flags: ignoreversion recursesubdirs

[Icons]
Name: "{group}\Kine"; Filename: "{app}\Kine.exe"
Name: "{group}\Uninstall Kine"; Filename: "{uninstallexe}"
Name: "{autodesktop}\Kine"; Filename: "{app}\Kine.exe"; Tasks: desktopicon

[Run]
Filename: "{app}\Kine.exe"; Description: "Start Kine"; Flags: nowait postinstall skipifsilent

; no [UninstallDelete] on purpose: the user's scenes, settings and autosaves are not ours to remove.
