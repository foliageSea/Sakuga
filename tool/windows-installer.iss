; Compile with build_windows_installer.ps1 after building Windows Release.
#ifndef BuildName
  #error BuildName is required (pass /DBuildName=X.Y.Z to ISCC).
#endif
#ifndef BuildNumber
  #error BuildNumber is required (pass /DBuildNumber=N to ISCC).
#endif

#define RepoRoot AddBackslash(SourcePath) + ".."
#define ReleaseDir RepoRoot + "\build\windows\x64\runner\Release"
#define AppExe "Sakuga.exe"

[Setup]
; Keep this GUID unchanged so new versions upgrade the existing per-user install.
AppId={{C2128BC9-15A4-4B0D-B27A-6EC12F7C1D03}
AppName=Sakuga
AppVersion={#BuildName}
AppVerName=Sakuga {#BuildName} ({#BuildNumber})
AppPublisher=com.foliage
VersionInfoVersion={#BuildName}.{#BuildNumber}
VersionInfoProductName=Sakuga
VersionInfoProductVersion={#BuildName}.{#BuildNumber}
ArchitecturesAllowed=x64os
ArchitecturesInstallIn64BitMode=x64os
PrivilegesRequired=lowest
DefaultDirName={localappdata}\Programs\Sakuga
UsePreviousAppDir=yes
DisableProgramGroupPage=yes
UninstallDisplayIcon={app}\{#AppExe}
SetupIconFile={#RepoRoot}\windows\runner\resources\app_icon.ico
OutputDir={#RepoRoot}\dist
OutputBaseFilename=Sakuga-{#BuildName}-{#BuildNumber}-windows-x64-setup
Compression=lzma2
SolidCompression=yes
WizardStyle=modern
RestartApplications=no

[Tasks]
Name: "desktopicon"; Description: "{cm:CreateDesktopIcon}"; GroupDescription: "{cm:AdditionalIcons}"; Flags: unchecked

[Files]
; Keep the full Flutter bundle (including native libraries and nested data).
; Root-level copies of the notices, if staged for the ZIP, are ignored here.
Source: "{#ReleaseDir}\*"; DestDir: "{app}"; Excludes: "\LICENSE,\THIRD_PARTY_NOTICES.md"; Flags: ignoreversion recursesubdirs createallsubdirs
Source: "{#RepoRoot}\LICENSE"; DestDir: "{app}"; Flags: ignoreversion
Source: "{#RepoRoot}\THIRD_PARTY_NOTICES.md"; DestDir: "{app}"; Flags: ignoreversion

[Icons]
Name: "{userprograms}\Sakuga"; Filename: "{app}\{#AppExe}"; WorkingDir: "{app}"
Name: "{userdesktop}\Sakuga"; Filename: "{app}\{#AppExe}"; WorkingDir: "{app}"; Tasks: desktopicon

; Use Inno Setup's normal uninstall log. Do not delete user files or app data.
