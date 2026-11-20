#define AppName "Recovery & Backup OS"
#define SourceRoot SourcePath

[Setup]
AppId={{A62C83B6-FFB8-40CC-A9F6-5D8482D71FA5}
AppName={#AppName}
AppVersion=1.0.1
DefaultDirName={localappdata}\Programs\RecoveryBackupOS
DefaultGroupName={#AppName}
OutputDir=dist
OutputBaseFilename=RecoveryBackupOS-Installer
Compression=none
SolidCompression=no
WizardStyle=classic
PrivilegesRequired=lowest
ArchitecturesAllowed=x64compatible
UninstallDisplayName={#AppName}
UninstallDisplayIcon={app}\RecoveryConsole.exe
SetupIconFile={#SourceRoot}\assets\visual-identity\v1.0.0\original\backup-restore-app.ico

[Languages]
Name: "english"; MessagesFile: "compiler:Default.isl"

[Tasks]
Name: "desktopicon"; Description: "Create a desktop shortcut"; Flags: unchecked

[Files]
Source: "{#SourceRoot}\RecoveryConsole.exe"; DestDir: "{app}"; Flags: ignoreversion
Source: "{#SourceRoot}\RecoveryConsole.Worker.exe"; DestDir: "{app}"; Flags: ignoreversion
Source: "{#SourceRoot}\FirmwareHelper.exe"; DestDir: "{app}"; Flags: ignoreversion
Source: "{#SourceRoot}\installer.ps1"; DestDir: "{app}"; Flags: ignoreversion
Source: "{#SourceRoot}\README.txt"; DestDir: "{app}"; Flags: ignoreversion
Source: "{#SourceRoot}\ERROR-CODES.txt"; DestDir: "{app}"; Flags: ignoreversion
Source: "{#SourceRoot}\build.ps1"; DestDir: "{app}"; Flags: ignoreversion
Source: "{#SourceRoot}\make-package.ps1"; DestDir: "{app}"; Flags: ignoreversion
Source: "{#SourceRoot}\assets\*"; DestDir: "{app}\assets"; Flags: ignoreversion recursesubdirs createallsubdirs
Source: "{#SourceRoot}\resources\*"; DestDir: "{app}\resources"; Flags: ignoreversion recursesubdirs createallsubdirs
Source: "{#SourceRoot}\source\*"; DestDir: "{app}\source"; Flags: ignoreversion recursesubdirs createallsubdirs

[Icons]
Name: "{group}\{#AppName}"; Filename: "{app}\RecoveryConsole.exe"; WorkingDir: "{app}"
Name: "{autodesktop}\{#AppName}"; Filename: "{app}\RecoveryConsole.exe"; WorkingDir: "{app}"; Tasks: desktopicon

[Run]
Filename: "{app}\RecoveryConsole.exe"; Description: "Launch {#AppName}"; Flags: shellexec nowait postinstall skipifsilent

[Code]
var
  MaintenancePage: TInputOptionWizardPage;
  ExistingDir: String;
  FoundExisting: Boolean;

procedure InitializeWizard;
begin
  FoundExisting := RegQueryStringValue(HKCU,
    'Software\Microsoft\Windows\CurrentVersion\Uninstall\{A62C83B6-FFB8-40CC-A9F6-5D8482D71FA5}_is1',
    'Inno Setup: App Path', ExistingDir);
  if FoundExisting then
    FoundExisting := FileExists(AddBackslash(ExistingDir) + 'unins000.exe');
  if FoundExisting then begin
    MaintenancePage := CreateInputOptionPage(wpWelcome, 'Existing installation found',
      'Choose how to manage the installed application.',
      'Installed at: ' + ExistingDir + #13#10#13#10 +
      'These options affect application files only. Recovery partitions, firmware entries and backup images are not removed.',
      True, False);
    MaintenancePage.Add('Update the installed application');
    MaintenancePage.Add('Uninstall and reinstall the application');
    MaintenancePage.Add('Uninstall the application');
    MaintenancePage.SelectedValueIndex := 0;
  end;
end;

function RunExistingUninstaller: Boolean;
var ResultCode: Integer;
begin
  Result := False;
  if not FileExists(AddBackslash(ExistingDir) + 'unins000.exe') then begin
    MsgBox('The existing uninstaller is unavailable.', mbError, MB_OK);
    Exit;
  end;
  if not Exec(AddBackslash(ExistingDir) + 'unins000.exe', '/SILENT /NORESTART',
    ExistingDir, SW_SHOW, ewWaitUntilTerminated, ResultCode) then begin
    MsgBox('Unable to start the existing uninstaller.', mbError, MB_OK);
    Exit;
  end;
  if ResultCode <> 0 then begin
    MsgBox('The existing uninstaller failed or was cancelled. Code: ' + IntToStr(ResultCode), mbError, MB_OK);
    Exit;
  end;
  Result := True;
end;

function NextButtonClick(CurPageID: Integer): Boolean;
begin
  Result := True;
  if FoundExisting then begin
    if (CurPageID = wpSelectDir) and (CompareText(RemoveBackslashUnlessRoot(WizardDirValue), RemoveBackslashUnlessRoot(ExistingDir)) <> 0) then begin
      MsgBox('Update and reinstall must use the existing installation folder.', mbError, MB_OK);
      Result := False;
      Exit;
    end;
    if (CurPageID = MaintenancePage.ID) and (MaintenancePage.SelectedValueIndex = 2) then begin
      Result := False;
      if MsgBox('Uninstall the application files? Recovery partitions and backup images will remain.', mbConfirmation, MB_YESNO) = IDYES then
        if RunExistingUninstaller then begin
          MsgBox('The application has been uninstalled. Recovery partitions and backup images were not removed.', mbInformation, MB_OK);
          WizardForm.Close;
        end;
    end;
  end;
end;

function PrepareToInstall(var NeedsRestart: Boolean): String;
begin
  Result := '';
  if FoundExisting then begin
    if MaintenancePage.SelectedValueIndex = 1 then
      if not RunExistingUninstaller then Result := 'Reinstallation stopped because the previous application could not be uninstalled.';
  end;
end;
