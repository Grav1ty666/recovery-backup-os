#define AppName "Recovery & Backup OS"
#define SourceRoot SourcePath

[Setup]
AppId={{A62C83B6-FFB8-40CC-A9F6-5D8482D71FA5}
AppName={#AppName}
AppVersion=1.1.0
SetupIconFile=assets\visual-identity\v1.0.0\original\backup-restore-app.ico
DefaultDirName={localappdata}\Programs\RecoveryBackupOS
DefaultGroupName={#AppName}
OutputDir=..\recovery-build
OutputBaseFilename=RecoveryBackupOS-Setup-v1.1.0
Compression=none
SolidCompression=no
WizardStyle=classic
PrivilegesRequired=lowest
CloseApplications=no
ArchitecturesAllowed=x64compatible
UninstallDisplayName={#AppName}

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
Source: "{#SourceRoot}\assets\*"; DestDir: "{app}\assets"; Flags: ignoreversion recursesubdirs createallsubdirs
Source: "{#SourceRoot}\resources\*"; DestDir: "{app}\resources"; Flags: ignoreversion recursesubdirs createallsubdirs

[Icons]
Name: "{group}\{#AppName}"; Filename: "{app}\RecoveryConsole.exe"; WorkingDir: "{app}"
Name: "{autodesktop}\{#AppName}"; Filename: "{app}\RecoveryConsole.exe"; WorkingDir: "{app}"; Tasks: desktopicon

[Run]
Filename: "{app}\RecoveryConsole.exe"; Description: "Launch {#AppName} (requires administrator permission)"; Verb: "runas"; Flags: shellexec postinstall skipifsilent

[Code]
var
  MaintenancePage: TInputOptionWizardPage;
  ExistingDir: String;
  FoundExisting: Boolean;

function RecoveryApplicationRunning(var CheckFailed: Boolean): Boolean;
var ResultCode: Integer; Output: AnsiString; CommandLine, OutputFile: String;
begin
  Result := False;
  CheckFailed := True;
  OutputFile := ExpandConstant('{tmp}\recovery-running-processes.txt');
  CommandLine := '/D /C ""' + ExpandConstant('{sys}\tasklist.exe') + '" /NH /FO CSV > "' + OutputFile + '" 2>nul"';
  if not Exec(ExpandConstant('{cmd}'), CommandLine, '', SW_HIDE, ewWaitUntilTerminated, ResultCode) then Exit;
  if ResultCode <> 0 then Exit;
  if not LoadStringFromFile(OutputFile, Output) then Exit;
  CheckFailed := False;
  Result := (Pos('"recoveryconsole.exe"', Lowercase(String(Output))) > 0) or
            (Pos('"recoveryconsole.worker.exe"', Lowercase(String(Output))) > 0);
end;

function EnsureRecoveryApplicationClosed: Boolean;
var CheckFailed: Boolean;
begin
  Result := False;
  while RecoveryApplicationRunning(CheckFailed) do begin
    if MsgBox('Recovery & Backup OS is still running.' + #13#10#13#10 +
      'Finish any active disk operation and close the application, then choose Retry. ' +
      'Setup will not force it to close.', mbError, MB_RETRYCANCEL) <> IDRETRY then Exit;
  end;
  if CheckFailed then begin
    MsgBox('Setup could not check whether Recovery & Backup OS is running. Close the application and try setup again.', mbError, MB_OK);
    Exit;
  end;
  Result := True;
end;

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
      if not EnsureRecoveryApplicationClosed then Exit;
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
  if not EnsureRecoveryApplicationClosed then begin
    Result := 'Installation stopped because the application may still be running.';
    Exit;
  end;
  if FoundExisting then begin
    if MaintenancePage.SelectedValueIndex = 1 then
      if not RunExistingUninstaller then Result := 'Reinstallation stopped because the previous application could not be uninstalled.';
  end;
end;
