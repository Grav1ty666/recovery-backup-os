# 打包为文件夹。不得将目标设置在源项目目录内。
param([Parameter(Mandatory)][string]$Destination)
$ErrorActionPreference = 'Stop'
$root = (Resolve-Path -LiteralPath $PSScriptRoot).Path.TrimEnd('\')
$target = [IO.Path]::GetFullPath($Destination).TrimEnd('\')
if ($target.Equals($root,[StringComparison]::OrdinalIgnoreCase) -or $target.StartsWith($root+'\',[StringComparison]::OrdinalIgnoreCase)) { throw '打包目录不能位于源项目内部。' }
if (Test-Path -LiteralPath $target) { throw '目标已存在，拒绝覆盖。' }
& (Join-Path $root 'build.ps1')
New-Item -ItemType Directory -Force -Path (Split-Path -Parent $target) | Out-Null
Copy-Item -LiteralPath $root -Destination $target -Recurse
Write-Host "文件夹包已生成：$target"
