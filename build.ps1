$ErrorActionPreference = 'Stop'
$Root = $PSScriptRoot
$Compiler = Join-Path $env:WINDIR 'Microsoft.NET\Framework64\v4.0.30319\csc.exe'
$Icon = Join-Path $Root 'assets\visual-identity\v1.0.0\original\backup-restore-app.ico'
$Manifest = Join-Path $Root 'source\admin.manifest'
& $Compiler /nologo /target:exe /platform:x64 /codepage:65001 "/win32manifest:$Manifest" "/win32icon:$Icon" "/out:$Root\RecoveryConsole.Worker.exe" "$Root\source\Worker.cs"
if ($LASTEXITCODE -ne 0) { throw 'Worker compilation failed.' }
& $Compiler /nologo /target:winexe /platform:x64 /codepage:65001 "/win32manifest:$Manifest" "/win32icon:$Icon" "/out:$Root\RecoveryConsole.exe" /reference:System.Windows.Forms.dll "$Root\source\Launcher.cs"
if ($LASTEXITCODE -ne 0) { throw 'Launcher compilation failed.' }
& $Compiler /nologo /target:exe /platform:x64 /codepage:65001 "/out:$Root\FirmwareHelper.exe" "$Root\source\FirmwareHelper.cs" "$Root\source\FirmwareBoot.cs"
if ($LASTEXITCODE -ne 0) { throw 'Firmware helper compilation failed.' }
Copy-Item -LiteralPath "$Root\source\installer.ps1" -Destination "$Root\installer.ps1" -Force
Copy-Item -LiteralPath "$Root\source\start.sh","$Root\source\recovery-runtime.sh" -Destination "$Root\assets" -Force
Write-Host 'Build complete. No disk operations were performed.'
