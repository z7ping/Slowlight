#ifndef MyAppVersion
  #define MyAppVersion "0.0.0"
#endif

#define MyAppName "所行映我 · Slowlight"
#define MyExeName "Slowlight.exe"
#define MyAppUserModelId "Slowlight"

[Setup]
AppId=z7ping.Slowlight
AppName={#MyAppName}
AppVersion={#MyAppVersion}
AppPublisher=z7ping
DefaultDirName={localappdata}\Programs\Slowlight
DisableProgramGroupPage=yes
PrivilegesRequired=lowest
ArchitecturesAllowed=x64compatible
ArchitecturesInstallIn64BitMode=x64compatible
OutputDir=..\..\..\dist\windows
OutputBaseFilename=Slowlight-v{#MyAppVersion}-windows-x64-setup
SetupIconFile=..\runner\resources\app_icon.ico
UninstallDisplayIcon={app}\{#MyExeName}
Compression=lzma2
SolidCompression=yes
WizardStyle=modern

[Files]
Source: "..\..\build\windows\x64\runner\Release\*"; DestDir: "{app}"; Flags: ignoreversion recursesubdirs createallsubdirs
Source: "..\..\..\LICENSE"; DestDir: "{app}"; Flags: ignoreversion
Source: "..\..\..\THIRD_PARTY_NOTICES.md"; DestDir: "{app}"; Flags: ignoreversion

[InstallDelete]
Type: files; Name: "{userprograms}\所行映我.lnk"

[Icons]
Name: "{userprograms}\所行映我"; Filename: "{app}\{#MyExeName}"; WorkingDir: "{app}"; IconFilename: "{app}\{#MyExeName}"; AppUserModelID: "{#MyAppUserModelId}"; Comment: "{#MyAppName}"

[Run]
Filename: "{app}\{#MyExeName}"; Description: "启动所行映我"; Flags: nowait postinstall skipifsilent
