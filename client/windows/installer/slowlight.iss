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

[Registry]
; Register the credential-free browser return URL for the current user.
Root: HKCU; Subkey: "Software\Classes\slowlight"; ValueType: string; ValueName: ""; ValueData: "URL:Slowlight"; Flags: uninsdeletekey
Root: HKCU; Subkey: "Software\Classes\slowlight"; ValueType: string; ValueName: "URL Protocol"; ValueData: ""
Root: HKCU; Subkey: "Software\Classes\slowlight\DefaultIcon"; ValueType: string; ValueName: ""; ValueData: "{app}\resources\{#MyAppIconName}"
Root: HKCU; Subkey: "Software\Classes\slowlight\shell\open\command"; ValueType: string; ValueName: ""; ValueData: """{app}\{#MyExeName}"" ""%1"""

[Run]
Filename: "{app}\{#MyExeName}"; Description: "启动所行映我"; Flags: nowait postinstall skipifsilent
