#if GetEnv("SLOWLIGHT_WINDOWS_VERSION") != ""
  #define MyAppVersion GetEnv("SLOWLIGHT_WINDOWS_VERSION")
#else
  #define MyAppVersion "0.0.0"
#endif

#define MyAppName "所行映我 · Slowlight"
#define MyExeName "Slowlight.exe"
#define MyAppUserModelId "z7ping.Slowlight"
#define MyAppIconName "slowlight.ico"

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
UninstallDisplayIcon={app}\resources\{#MyAppIconName}
CloseApplications=yes
CloseApplicationsFilter={#MyExeName}
RestartApplications=no
Compression=lzma2
SolidCompression=yes
WizardStyle=modern

[Languages]
Name: "chinesesimplified"; MessagesFile: "ChineseSimplified.isl"

[Files]
Source: "..\..\build\windows\x64\runner\Release\*"; DestDir: "{app}"; Flags: ignoreversion recursesubdirs createallsubdirs
Source: "..\runner\resources\app_icon.ico"; DestDir: "{app}\resources"; DestName: "{#MyAppIconName}"; Flags: ignoreversion
Source: "..\..\..\LICENSE"; DestDir: "{app}"; Flags: ignoreversion
Source: "..\..\..\THIRD_PARTY_NOTICES.md"; DestDir: "{app}"; Flags: ignoreversion

[InstallDelete]
Type: files; Name: "{userprograms}\所行映我.lnk"

[Icons]
Name: "{userprograms}\所行映我"; Filename: "{app}\{#MyExeName}"; WorkingDir: "{app}"; IconFilename: "{app}\resources\{#MyAppIconName}"; IconIndex: 0; AppUserModelID: "{#MyAppUserModelId}"; Comment: "{#MyAppName}"

[Run]
Filename: "{app}\{#MyExeName}"; Description: "启动所行映我"; Flags: nowait postinstall skipifsilent
