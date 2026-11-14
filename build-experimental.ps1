# 在包含 source、assets 和 resources 的项目文件夹中构建 Windows EXE。
# GRUB 的 assets/grubx64.efi 由 grub-mkstandalone 单独构建；不自动访问互联网。
$ErrorActionPreference = 'Stop'
$Root = $PSScriptRoot
$Compiler = Join-Path $env:WINDIR 'Microsoft.NET\Framework64\v4.0.30319\csc.exe'
if (-not (Test-Path -LiteralPath $Compiler)) { throw '缺少 .NET Framework C# 编译器。' }
& $Compiler /nologo /target:exe /platform:x64 /codepage:65001 "/out:$Root\RecoveryConsole.Worker.exe" "$Root\source\Worker.cs"
if ($LASTEXITCODE -ne 0) { throw 'Worker 编译失败。' }
& $Compiler /nologo /target:winexe /platform:x64 /codepage:65001 "/win32manifest:$Root\source\admin.manifest" "/out:$Root\RecoveryConsole.exe" "$Root\source\Launcher.cs"
if ($LASTEXITCODE -ne 0) { throw 'Launcher 编译失败。' }
& $Compiler /nologo /target:exe /platform:x64 /codepage:65001 "/out:$Root\FirmwareHelper.exe" "$Root\source\FirmwareHelper.cs" "$Root\source\FirmwareBootDraft.cs"
if ($LASTEXITCODE -ne 0) { throw 'FirmwareHelper 编译失败。' }
Copy-Item -LiteralPath "$Root\source\installer.ps1" -Destination "$Root\installer.ps1" -Force
Copy-Item -LiteralPath "$Root\source\start.sh","$Root\source\recovery-runtime.sh" -Destination "$Root\assets" -Force
Write-Host '实验构建已生成。不会执行部署。'
