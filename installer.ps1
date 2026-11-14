# 部分功能尚未完成端到端验证。
# 使用未分配空间；不足时可经确认压缩 NTFS 卷。创建及固件写入各自确认。
Set-StrictMode -Version Latest
$ErrorActionPreference = 'Stop'
$Project = Split-Path -Parent $MyInvocation.MyCommand.Path
$EspBytes = [uint64](2GB)
$EspType = '{c12a7328-f81f-11d2-ba4b-00a0c93ec93b}'
$TranscriptStarted = $false
$LogPath = $null
$ExitCode = 0
$logName = 'run_{0}_{1}.log' -f (Get-Date -Format 'yyyyMMdd_HHmmss_fff'), $PID
foreach ($logDir in @((Join-Path $Project 'logs'), (Join-Path $env:LOCALAPPDATA 'ClonezillaRecovery\logs'))) {
    try {
        New-Item -ItemType Directory -Path $logDir -Force | Out-Null
        $candidate = Join-Path $logDir $logName
        Start-Transcript -LiteralPath $candidate -ErrorAction Stop | Out-Null
        $LogPath = $candidate
        $TranscriptStarted = $true
        break
    } catch { }
}
if (-not $TranscriptStarted) { Write-Warning '0xE001000A' }
$script:DiskChangesStarted = $false
# Product-specific codes; detailed errors go to the project log.
function Get-ProductErrorCode([string]$Message) {
    switch -Regex ($Message) {
        'cancelled' { return '0xE0010001' }
        'Administrator privileges' { return '0xE0010002' }
        'Secure Boot' { return '0xE0010003' }
        'BitLocker|encrypted|encryption|decrypted' { return '0xE0010004' }
        'Invalid .*number|not found or not unique|Select an option' { return '0xE0010005' }
        'contiguous space|shrink limit|too small|unallocated space|free|capacity|size is invalid' { return '0xE0010006' }
        'Missing file|missing|inaccessible|unavailable' { return '0xE0010007' }
        'UEFI|Firmware|boot entry' { return '0xE0010008' }
        'disk|partition|volume|store|baseline|backup' { return '0xE0010009' }
        default { return '0xE00100FF' }
    }
}
function Log-Detail([string]$Code, [string]$Detail) {
    try { Add-Content -LiteralPath (Join-Path $Project 'error-details.log') -Value ("{0:s} {1} {2}" -f (Get-Date),$Code,$Detail) -Encoding UTF8 } catch { }
}
function Report-Detail([string]$Code, [string]$Detail) {
    Log-Detail $Code $Detail
    Write-Host ('  Error: ' + $Code) -ForegroundColor Yellow
}
function Confirm-Enter([string]$Message) {
    Write-Host "  $Message (press Enter to continue; any other key cancels)" -NoNewline
    $key = $Host.UI.RawUI.ReadKey('NoEcho,IncludeKeyDown')
    Write-Host ''
    if ($key.VirtualKeyCode -ne 13) { throw 'Operation cancelled.' }
}
function Show-ExistingStore($Volume) {
    Write-Host ("`nFound backup volume: {0}" -f $Volume.FileSystemLabel)
    $matches = @()
    try { $matches = @(Get-Partition -Volume $Volume -ErrorAction Stop) } catch { Report-Detail '0xE0010009' ($_.Exception.ToString()) }
    foreach ($partition in $matches) {
        $disk = Get-Disk -Number $partition.DiskNumber
        Write-Host ("  Disk {0} ({1}), partition {2}, GUID {3}" -f $partition.DiskNumber,$disk.FriendlyName,$partition.PartitionNumber,$partition.Guid)
    }
    Write-Host ("  Filesystem: {0}; capacity: {1:N2} GB; free: {2:N2} GB" -f $Volume.FileSystem,($Volume.Size/1GB),($Volume.SizeRemaining/1GB))
    if ($Volume.FileSystem -ne 'exFAT') { Write-Warning 'Volume is not exFAT; it cannot be used as the image store.'; return }
    # 没有盘符时优先使用 Windows 返回的卷 GUID 路径，不为扫描修改分区属性。
    $volumePath = [string]$Volume.Path
    if ([string]::IsNullOrWhiteSpace($volumePath) -and $Volume.DriveLetter) { $volumePath = [string]$Volume.DriveLetter + ':\' }
    if ([string]::IsNullOrWhiteSpace($volumePath)) { Write-Warning 'Volume path unavailable; cannot inspect images.'; return }
    try {
        $root = [IO.Path]::Combine($volumePath, 'partimag')
        if (-not [IO.Directory]::Exists($root)) { Write-Warning 'The partimag directory is missing or inaccessible.'; return }
        $dirs = @([IO.Directory]::GetDirectories($root))
        $base = @($dirs | Where-Object { [IO.Path]::GetFileName($_) -eq 'BACKUP_OS' })
        $baseMarker = [IO.Path]::Combine($root, '.BACKUP_OS.incomplete')
        if ($base.Count -gt 0) {
            if ([IO.File]::Exists($baseMarker)) { Write-Warning 'BACKUP_OS has an incomplete marker and cannot be restored.' }
            else { Write-Host '  BACKUP_OS found; image has not been validated.' }
        } elseif ([IO.File]::Exists($baseMarker)) { Write-Warning 'Incomplete baseline marker found; image directory missing.' }
        else {
            Write-Host '  BACKUP_OS not found; recovery will abort and reboot.'
        }
        $backups = @($dirs | Where-Object { [IO.Path]::GetFileName($_) -match '^auto_backup_[0-9]{8}_[0-9]{6}$' } | Sort-Object -Descending)
        if ($backups.Count -eq 0) { Write-Host '  No automatic backups found.' }
        foreach ($entry in $backups) {
            $name = [IO.Path]::GetFileName($entry)
            $marker = [IO.Path]::Combine($root, ('.' + $name + '.incomplete'))
            if ([IO.File]::Exists($marker)) { Write-Warning ("  $name — incomplete marker present") }
            else { Write-Host ("  $name — found; not yet checked") }
        }
        foreach ($markerPath in [IO.Directory]::GetFiles($root, '.auto_backup_*.incomplete')) {
            $markerName = [IO.Path]::GetFileName($markerPath)
            $imageName = $markerName.Substring(1, $markerName.Length - 1 - '.incomplete'.Length)
            if (-not [IO.Directory]::Exists([IO.Path]::Combine($root, $imageName))) { Write-Warning ("  $imageName — incomplete marker; image directory missing") }
        }
    } catch { Report-Detail '0xE0010007' ($_.Exception.ToString()) }
}
function Get-StoreRoot($Volume) {
    $path = [string]$Volume.Path
    if ([string]::IsNullOrWhiteSpace($path) -and $Volume.DriveLetter) { $path = [string]$Volume.DriveLetter + ':\' }
    if ([string]::IsNullOrWhiteSpace($path)) { throw 'Image store path unavailable.' }
    return $path
}
function Set-ExistingBackupAsBaseline($Volume) {
    if ($Volume.FileSystem -ne 'exFAT') { throw 'Image store is not exFAT.' }
    if ([string]::IsNullOrWhiteSpace([string]$Volume.UniqueId)) { throw 'Image store identifier unavailable.' }
    $storeRoot = Get-StoreRoot $Volume
    $images = [IO.Path]::Combine($storeRoot, 'partimag')
    if (-not [IO.Directory]::Exists($images)) { throw 'Image directory missing or inaccessible.' }
    $baseline = [IO.Path]::Combine($images, 'BACKUP_OS')
    $baselineMarker = [IO.Path]::Combine($images, '.BACKUP_OS.incomplete')
    if ([IO.Directory]::Exists($baseline) -or [IO.File]::Exists($baselineMarker)) { throw 'Baseline or incomplete marker already exists; refusing to overwrite.' }
    $choices = @([IO.Directory]::GetDirectories($images) | Where-Object { [IO.Path]::GetFileName($_) -match '^auto_backup_[0-9]{8}_[0-9]{6}$' } | Sort-Object -Descending)
    if ($choices.Count -eq 0) { throw 'No automatic backups available.' }
    for ($i=0; $i -lt $choices.Count; $i++) { Write-Host ("  {0}: {1}" -f ($i+1),[IO.Path]::GetFileName($choices[$i])) }
    [uint32]$selection = 0
    if (-not [uint32]::TryParse((Read-Host '  Select the backup number to use as baseline'),[ref]$selection) -or $selection -lt 1 -or $selection -gt $choices.Count) { throw 'Invalid backup number.' }
    $selected = $choices[$selection-1]; $name = [IO.Path]::GetFileName($selected)
    if ([IO.File]::Exists([IO.Path]::Combine($images, ('.' + $name + '.incomplete')))) { throw 'Backup is marked incomplete.' }
    if (-not [IO.File]::Exists([IO.Path]::Combine($selected, 'parts'))) { throw 'Backup partition list is missing.' }
    if (([IO.File]::GetAttributes($selected) -band [IO.FileAttributes]::ReparsePoint) -ne 0) { throw 'Links and reparse points are not supported.' }
    Write-Warning "Rename $name to BACKUP_OS; this does not validate the image."
    Confirm-Enter 'Confirm baseline selection'
    $current = @(Get-Volume | Where-Object { $_.FileSystemLabel -eq 'BACKUP_OS' })
    if ($current.Count -ne 1 -or [string]$current[0].UniqueId -ne [string]$Volume.UniqueId -or [IO.Directory]::Exists($baseline) -or [IO.File]::Exists($baselineMarker) -or [IO.File]::Exists([IO.Path]::Combine($images, ('.' + $name + '.incomplete')))) { throw 'Image store changed; operation stopped.' }
    [IO.Directory]::Move($selected, $baseline)
    Write-Host '  Baseline set. Clonezilla will check it before recovery.'
}
function Export-LatestRecoveryLog($Volume) {
    $storeRoot = Get-StoreRoot $Volume
    $folder = [IO.Path]::Combine($storeRoot, 'recovery_logs')
    if (-not [IO.Directory]::Exists($folder)) { throw 'No recovery logs are available.' }
    $logs = @([IO.Directory]::GetFiles($folder, '*.log') | Sort-Object { [IO.File]::GetLastWriteTimeUtc($_) } -Descending)
    if ($logs.Count -eq 0) { throw 'Recovery log directory is empty.' }
    $outDir = Join-Path $Project 'logs'
    New-Item -ItemType Directory -Path $outDir -Force | Out-Null
    $out = Join-Path $outDir ('recovery_export_{0}_{1}.log' -f (Get-Date -Format 'yyyyMMdd_HHmmss_fff'),$PID)
    [IO.File]::Copy($logs[0], $out, $false)
    Write-Host "  Recovery log exported: $out"
}
function Uninstall-Recovery($StoreVolume, $BootVolumes) {
    if (@($BootVolumes).Count -ne 1) { throw 'Recovery ESP cannot be uniquely identified.' }
    $bootVolume = @($BootVolumes)[0]
    $boots = @(Get-Partition -Volume $bootVolume -ErrorAction Stop)
    $stores = @(Get-Partition -Volume $StoreVolume -ErrorAction Stop)
    if ($boots.Count -ne 1 -or $stores.Count -ne 1) { throw 'Partitions cannot be uniquely identified.' }
    $boot = $boots[0]; $store = $stores[0]
    $espType = 'c12a7328-f81f-11d2-ba4b-00a0c93ec93b'
    if (([string]$boot.GptType).Trim('{}').ToLowerInvariant() -ne $espType -or $boot.IsSystem -or $boot.IsBoot -or $store.IsSystem -or $store.IsBoot -or -not $boot.Guid -or -not $store.Guid -or [string]$boot.Guid -eq [string]$store.Guid) { throw 'Unsafe partition identity.' }
    $configPath = [IO.Path]::Combine([string]$bootVolume.Path, 'EFI\clonezilla\recovery.conf')
    $cfg = [IO.File]::ReadAllText($configPath)
    $found = [regex]::Matches($cfg, '(?m)^store_partuuid=([0-9a-fA-F-]+)\r?$')
    if ($found.Count -ne 1 -or $found[0].Groups[1].Value.ToLowerInvariant() -ne ([string]$store.Guid).Trim('{}').ToLowerInvariant()) { throw 'Backup store GUID does not match recovery configuration.' }
    $bootDisk=Get-Disk -Number $boot.DiskNumber; $storeDisk=Get-Disk -Number $store.DiskNumber
    Write-Host ("  Recovery ESP: disk {0}, partition {1}, {2:N2} GB, {3}" -f $boot.DiskNumber,$boot.PartitionNumber,($boot.Size/1GB),$boot.Guid)
    Write-Host ("  BACKUP_OS: disk {0}, partition {1}, {2:N2} GB, {3}" -f $store.DiskNumber,$store.PartitionNumber,($store.Size/1GB),$store.Guid)
    Write-Host '  WARNING: all backup images in BACKUP_OS will be permanently deleted.' -ForegroundColor Yellow
    Write-Host '  The released space will remain unallocated.'
    Confirm-Enter 'Confirm uninstall'
    $b=Get-Partition -DiskNumber $boot.DiskNumber -PartitionNumber $boot.PartitionNumber
    $v=Get-Partition -DiskNumber $store.DiskNumber -PartitionNumber $store.PartitionNumber
    if ([string]$b.Guid -ne [string]$boot.Guid -or [string]$v.Guid -ne [string]$store.Guid -or $b.Offset -ne $boot.Offset -or $v.Offset -ne $store.Offset -or $b.Size -ne $boot.Size -or $v.Size -ne $store.Size -or $b.IsSystem -or $b.IsBoot -or $v.IsSystem -or $v.IsBoot -or [string](Get-Disk -Number $boot.DiskNumber).UniqueId -ne [string]$bootDisk.UniqueId -or [string](Get-Disk -Number $store.DiskNumber).UniqueId -ne [string]$storeDisk.UniqueId -or [IO.File]::ReadAllText($configPath) -cne $cfg) { throw 'Partition identity changed; uninstall stopped.' }
    $script:DiskChangesStarted=$true
    Write-Host '  Removing matching firmware entries...'
    & (Join-Path $Project 'FirmwareHelper.exe') uninstall ([string]$boot.Guid)
    if ($LASTEXITCODE -ne 0) { throw 'UEFI entry removal failed; partitions were not removed.' }
    # Revalidate immediately before partition deletion.
    foreach($pair in @(@($boot,$bootDisk),@($store,$storeDisk))) {
        $current=Get-Partition -DiskNumber $pair[0].DiskNumber -PartitionNumber $pair[0].PartitionNumber
        if ([string]$current.Guid -ne [string]$pair[0].Guid -or $current.Offset -ne $pair[0].Offset -or $current.Size -ne $pair[0].Size -or $current.IsBoot -or $current.IsSystem -or [string](Get-Disk -Number $current.DiskNumber).UniqueId -ne [string]$pair[1].UniqueId) { throw 'Partition changed; automatic deletion stopped.' }
    }
    Write-Host '  Removing recovery ESP...'
    Remove-Partition -DiskNumber $boot.DiskNumber -PartitionNumber $boot.PartitionNumber -Confirm:$false -ErrorAction Stop
    $current=Get-Partition -DiskNumber $store.DiskNumber -PartitionNumber $store.PartitionNumber -ErrorAction Stop
    if ([string]$current.Guid -ne [string]$store.Guid -or $current.Offset -ne $store.Offset -or $current.Size -ne $store.Size -or $current.IsBoot -or $current.IsSystem) { throw 'Backup partition changed; deletion stopped.' }
    Write-Host '  Removing backup partition...'
    Remove-Partition -DiskNumber $store.DiskNumber -PartitionNumber $store.PartitionNumber -Confirm:$false -ErrorAction Stop
    Write-Host '  Uninstall complete. Released space is unallocated.' -ForegroundColor Green
}

function Pick-Disk([string]$Title) {
    Write-Host "`n$Title"
    $disks = @(Get-Disk)
    foreach ($disk in $disks) {
        $volumeItems = @()
        foreach ($partition in @(Get-Partition -DiskNumber $disk.Number -ErrorAction SilentlyContinue)) {
            if (-not $partition.DriveLetter) { continue }
            $letter = ([string]$partition.DriveLetter).ToUpperInvariant() + ':/'
            try {
                $volume = Get-Volume -Partition $partition -ErrorAction Stop
                $volumeItems += ('{0}  {1:N2} GB free' -f $letter, ($volume.SizeRemaining/1GB))
            } catch { $volumeItems += ($letter + '  free space unavailable') }
        }
        $volumeText = if ($volumeItems.Count -gt 0) { $volumeItems -join '   |   ' } else { 'no drive letter' }
        Write-Host ("  [{0}] {1}  ({2:N1} GB)" -f $disk.Number,$disk.FriendlyName,($disk.Size/1GB)) -ForegroundColor White
        # Windows Terminal uses ANSI sequences for bold values.
        $bold = "$([char]27)[1m"; $reset = "$([char]27)[22m"
        Write-Host ("  Volumes: {0}{1}{2}    Table: {0}{3}{2}" -f $bold,$volumeText,$reset,$disk.PartitionStyle) -ForegroundColor Gray
    }
    [uint32]$number = 0
    if (-not [uint32]::TryParse((Read-Host '  Enter disk number'), [ref]$number)) { throw 'Invalid disk number.' }
    $selected = @($disks | Where-Object Number -eq $number)
    if ($selected.Count -ne 1) { throw 'Disk not found or not unique.' }
    if ($selected[0].PartitionStyle -ne 'GPT' -or $selected[0].IsOffline -or $selected[0].IsReadOnly -or [string]::IsNullOrWhiteSpace($selected[0].UniqueId)) { throw 'Disk must be online, writable, GPT, and uniquely identified.' }
    return $selected[0]
}
function Verify-Disk($Old, [uint64]$Needed) {
    $current = Get-Disk -Number $Old.Number
    if ($current.UniqueId -ne $Old.UniqueId -or $current.PartitionStyle -ne 'GPT' -or $current.IsOffline -or $current.IsReadOnly -or $current.LargestFreeExtent -lt $Needed) { throw 'Disk identity or unallocated space changed.' }
}
function Get-ShrinkPlan($Old, [uint64]$Needed) {
    $disk = Get-Disk -Number $Old.Number
    if ($disk.UniqueId -ne $Old.UniqueId -or $disk.IsOffline -or $disk.IsReadOnly -or $disk.PartitionStyle -ne 'GPT') { throw 'Disk identity or status changed.' }
    if ($disk.LargestFreeExtent -ge $Needed) { return $null }
    # 不假设现有空闲区域与压缩后的空间相邻，因此须单独腾出完整连续空间。
    $shrinkBytes = [uint64]($Needed + 8MB)
    $plans = @()
    Write-Host ("Disk {0} needs about {1:N2} GB of contiguous space. Checking partitions:" -f $disk.Number,($shrinkBytes/1GB))
    foreach ($partition in @(Get-Partition -DiskNumber $disk.Number)) {
        $name = if ($partition.DriveLetter) { [string]$partition.DriveLetter + ':' } else { 'no drive letter' }
        $id = "Partition $($partition.PartitionNumber) ($name)"
        try {
            if (-not $partition.DriveLetter -or -not $partition.Guid) { Write-Host "  ${id}: skipped; no drive letter or partition GUID."; continue }
            $volume = Get-Volume -DriveLetter $partition.DriveLetter -ErrorAction Stop
            Write-Host ("  {0}: {1}, free {2:N2} GB" -f $id,$volume.FileSystem,($volume.SizeRemaining/1GB))
            if ($volume.FileSystem -ne 'NTFS') { Report-Detail '0xE0010009' 'Partition is not NTFS.'; continue }
            try { $encryption = Get-BitLockerVolume -MountPoint ($partition.DriveLetter + ':') -ErrorAction Stop }
            catch { Report-Detail '0xE0010004' ($_.Exception.ToString()); continue }
            if (-not $encryption) { Report-Detail '0xE0010004' 'BitLocker status unavailable.'; continue }
            if ([string]$encryption.VolumeStatus -ne 'FullyDecrypted') { Report-Detail '0xE0010004' ("Encryption status: {0}" -f [string]$encryption.VolumeStatus); continue }
            try { $limits = Get-PartitionSupportedSize -DiskNumber $disk.Number -PartitionNumber $partition.PartitionNumber -ErrorAction Stop }
            catch { Report-Detail '0xE0010006' ($_.Exception.ToString()); continue }
            $maxShrink = [math]::Max([double]0, ([double]$partition.Size - [double]$limits.SizeMin))
            Write-Host ("  Windows allows shrinking about {0:N2} GB; needed: {1:N2} GB." -f ($maxShrink/1GB),($shrinkBytes/1GB))
            if ($volume.SizeRemaining -lt ($shrinkBytes + 10GB)) { Report-Detail '0xE0010006' ("Free space required: {0:N2} GB including 10 GB reserve." -f (($shrinkBytes+10GB)/1GB)); continue }
            if ($partition.Size -le $shrinkBytes) { Report-Detail '0xE0010006' 'Partition is too small.'; continue }
            $newSize = [uint64]([math]::Floor(($partition.Size - $shrinkBytes) / 1MB) * 1MB)
            if ($newSize -lt $limits.SizeMin -or $newSize -ge $partition.Size) { Report-Detail '0xE0010006' 'Windows shrink limit is too small.'; continue }
            $plans += [pscustomobject]@{ DiskNumber=$disk.Number; DiskUniqueId=$disk.UniqueId; PartitionNumber=$partition.PartitionNumber; PartitionGuid=[string]$partition.Guid; Letter=$partition.DriveLetter; OldSize=[uint64]$partition.Size; NewSize=$newSize; Free=[uint64]$volume.SizeRemaining; Needed=$Needed }
            Write-Host '  Eligible for shrinking.'
        } catch { Report-Detail '0xE0010009' ($_.Exception.ToString()) }
    }
    if ($plans.Count -eq 0) { throw ("Disk {0} cannot provide the required contiguous space; see details above." -f $disk.Number) }
    return $plans | Sort-Object Free -Descending | Select-Object -First 1
}
function Apply-ShrinkPlan($Plan) {
    if ($null -eq $Plan) { return }
    $released = $Plan.OldSize - $Plan.NewSize
    $disk = Get-Disk -Number $Plan.DiskNumber
    $partition = Get-Partition -DiskNumber $Plan.DiskNumber -PartitionNumber $Plan.PartitionNumber
    $volume = Get-Volume -DriveLetter $Plan.Letter
    $limits = Get-PartitionSupportedSize -DiskNumber $Plan.DiskNumber -PartitionNumber $Plan.PartitionNumber
    if ($disk.UniqueId -ne $Plan.DiskUniqueId -or $disk.IsOffline -or $disk.IsReadOnly -or ([string]$partition.Guid) -ne $Plan.PartitionGuid -or $partition.Size -ne $Plan.OldSize -or $volume.FileSystem -ne 'NTFS' -or $volume.SizeRemaining -lt ($released + 10GB) -or $Plan.NewSize -lt $limits.SizeMin) { throw 'Disk or partition changed before shrinking.' }
    $encryption = Get-BitLockerVolume -MountPoint ($Plan.Letter + ':') -ErrorAction Stop
    if ([string]$encryption.VolumeStatus -ne 'FullyDecrypted') { throw 'Volume encryption status changed.' }
    $script:DiskChangesStarted = $true
    Resize-Partition -DiskNumber $Plan.DiskNumber -PartitionNumber $Plan.PartitionNumber -Size $Plan.NewSize -Confirm:$false -ErrorAction Stop
}
try {
    if (-not ([Security.Principal.WindowsPrincipal][Security.Principal.WindowsIdentity]::GetCurrent()).IsInRole([Security.Principal.WindowsBuiltInRole]::Administrator)) { throw 'Administrator privileges required.' }
    Write-Host 'RECOVERY & BACKUP OS' -ForegroundColor Cyan
    Write-Host ''
    Write-Host '[1/4] Checking system and existing backups...' -ForegroundColor Cyan
    $volumes = @(Get-Volume -ErrorAction Stop)
    $existingStores = @($volumes | Where-Object { $_.FileSystemLabel -eq 'BACKUP_OS' })
    # An ESP label alone is not unique to this tool: require our recovery files.
    $existingBoot = @($volumes | Where-Object {
        $_.FileSystemLabel -eq 'ESP' -and -not [string]::IsNullOrWhiteSpace([string]$_.Path) -and
        [IO.File]::Exists([IO.Path]::Combine([string]$_.Path, 'EFI\clonezilla\recovery.conf'))
    })
    if ($existingStores.Count -gt 0) {
        foreach ($existing in $existingStores) { Show-ExistingStore $existing }
        if ($existingStores.Count -gt 1) { Write-Warning 'Multiple backup volumes found; automatic selection is unsafe.' }
        Write-Host '  Backup partition found; deployment will not be repeated.' -ForegroundColor Yellow
        if ($existingStores.Count -eq 1) {
            Write-Host '  1  Set baseline     2  Export log     3  Uninstall     Enter Exit'
            $action = Read-Host '  Select an option'
            if ($action -eq '1') { Set-ExistingBackupAsBaseline $existingStores[0] }
            elseif ($action -eq '2') { Export-LatestRecoveryLog $existingStores[0] }
            elseif ($action -eq '3') { Uninstall-Recovery $existingStores[0] $existingBoot }
        }
        return
    }
    if ($existingBoot.Count -gt 0) { throw 'Existing recovery ESP found without a backup store; deployment stopped.' }
    # 若 Windows 完全隐藏了某个基本数据分区，无法仅凭 Get-Volume 排除它是现有仓库。
    $basicType = 'ebd0a0a2-b9e5-4433-87c0-68b6b72699c7'
    $unreadable = @(Get-Partition | Where-Object {
        ([string]$_.GptType).Trim('{}').ToLowerInvariant() -eq $basicType -and
        -not $_.DriveLetter -and ($_.IsHidden -or $_.NoDefaultDriveLetter) -and
        @($_ | Get-Volume -ErrorAction SilentlyContinue).Count -eq 0
    })
    if ($unreadable.Count -gt 0) { throw 'Unreadable hidden partition found; cannot rule out an existing backup store.' }
    if (-not (Get-Command Confirm-SecureBootUEFI -ErrorAction SilentlyContinue)) { throw 'Cannot check Secure Boot.' }
    if (Confirm-SecureBootUEFI) { throw 'Secure Boot must be disabled.' }
    if (-not (Get-Command Get-BitLockerVolume -ErrorAction SilentlyContinue)) { throw 'Cannot check BitLocker; operation stopped.' }
    $bit = Get-BitLockerVolume -MountPoint $env:SystemDrive
    if (-not $bit -or [string]$bit.VolumeStatus -ne 'FullyDecrypted') { throw 'Windows volume is encrypted or its status is unknown.' }
    $windows = Get-Partition -DriveLetter ($env:SystemDrive.Substring(0,1))
    $system = Get-Disk -Number $windows.DiskNumber
    if ($system.PartitionStyle -ne 'GPT' -or -not $system.Guid -or -not $windows.Guid) { throw 'Cannot identify Windows GPT disk or partition.' }
    $serial = ([string]$system.SerialNumber).Trim()
    $systemGuid = ([string]$system.Guid).Trim('{}').ToLowerInvariant()
    $matchesByGuid = @(Get-Disk | Where-Object { $_.PartitionStyle -eq 'GPT' -and ([string]$_.Guid).Trim('{}').ToLowerInvariant() -eq $systemGuid })
    if ($matchesByGuid.Count -ne 1) { throw 'Windows disk GPT identifier is not unique.' }
    $identityLine = "system_serial=$serial"
    if ($serial -notmatch '^[a-zA-Z0-9_.:-]+$') {
        $identityLine = 'identity_mode=ptuuid_only'
        Write-Warning 'Disk serial unavailable; GPT disk and partition GUIDs will identify the target.'
    }
    $required = @('assets\grubx64.efi','assets\start.sh','assets\recovery-runtime.sh','resources\live\vmlinuz','resources\live\initrd.img','resources\live\filesystem.squashfs','FirmwareHelper.exe')
    foreach ($name in $required) { if (-not (Test-Path -LiteralPath (Join-Path $Project $name) -PathType Leaf)) { throw "Missing file: $name" } }
    Write-Host "`n[2/4] Select disks" -ForegroundColor Cyan
    $espDisk = Pick-Disk 'Select the boot partition disk'
    $storeDisk = Pick-Disk 'Select the backup partition disk (may be the same)'
    # NTFS 已用量只是备份规模参考，压缩后的准确大小无法预知。
    $windowsVolume = Get-Volume -DriveLetter ($env:SystemDrive.Substring(0,1)) -ErrorAction SilentlyContinue
    if (-not $windowsVolume -or $windowsVolume.FileSystem -ne 'NTFS' -or $windowsVolume.Size -le 0 -or $windowsVolume.SizeRemaining -gt $windowsVolume.Size) { throw 'Cannot read Windows NTFS usage.' }
    $usedBytes = [uint64]($windowsVolume.Size - $windowsVolume.SizeRemaining)
    # 按 Windows 已用空间的 60% 计算，向上取整至 10 GB 档位。
    $sizeGB = [uint64]([math]::Ceiling((([double]$usedBytes / 1GB) * 0.6) / 10) * 10)
    if ($sizeGB -lt 1 -or $sizeGB -gt 100000) { throw 'Calculated backup partition size is invalid or too large.' }
    $storeBytes = [uint64]($sizeGB * 1GB)
    if ($espDisk.Number -eq $storeDisk.Number) {
        $espPlan = Get-ShrinkPlan $espDisk ($EspBytes + $storeBytes + 64MB)
        $storePlan = $null
    } else {
        $espPlan = Get-ShrinkPlan $espDisk ($EspBytes + 32MB)
        $storePlan = Get-ShrinkPlan $storeDisk ($storeBytes + 32MB)
    }
    Write-Host "`n[3/4] Review deployment" -ForegroundColor Cyan
    Write-Host ("  Boot: disk {0} ({1}), create and format 2 GB FAT32" -f $espDisk.Number,$espDisk.FriendlyName)
    Write-Host ("  Backup: disk {0} ({1}), create and format {2} GB exFAT" -f $storeDisk.Number,$storeDisk.FriendlyName,$sizeGB)
    foreach ($plan in @($espPlan,$storePlan)) {
        if ($null -ne $plan) { Write-Host ("  Shrink disk {0}, {1}: from {2:N2} GB to {3:N2} GB" -f $plan.DiskNumber,$plan.Letter,($plan.OldSize/1GB),($plan.NewSize/1GB)) }
    }
    Write-Host '  Write boot files and register a UEFI entry. Partition or boot errors may affect data and startup.'
    Confirm-Enter 'Confirm all listed disk operations'
    Write-Host "`n[4/4] Deploying. Keep this window open..." -ForegroundColor Cyan
    Write-Host '  Preparing disk space...' -ForegroundColor Gray
    Apply-ShrinkPlan $espPlan
    Apply-ShrinkPlan $storePlan
    if ($espDisk.Number -eq $storeDisk.Number) { Verify-Disk $espDisk ($EspBytes + $storeBytes + 64MB) }
    else { Verify-Disk $espDisk ($EspBytes + 32MB); Verify-Disk $storeDisk ($storeBytes + 32MB) }
    Verify-Disk $espDisk ($EspBytes + 32MB)
    # 未格式化分区不分配盘符，避免资源管理器抢先弹出格式化提示。
    $script:DiskChangesStarted = $true
    Write-Host '  Creating boot partition...' -ForegroundColor Gray
    $esp = New-Partition -DiskNumber $espDisk.Number -Size $EspBytes
    if (-not $esp.Guid) { throw 'New boot partition has no GUID.' }
    Set-Partition -DiskNumber $espDisk.Number -PartitionNumber $esp.PartitionNumber -NoDefaultDriveLetter $true -Confirm:$false -ErrorAction Stop
    $esp = Get-Partition -DiskNumber $espDisk.Number -PartitionNumber $esp.PartitionNumber
    Format-Volume -Partition $esp -FileSystem FAT32 -NewFileSystemLabel ESP -Confirm:$false -Force | Out-Null
    # 通过卷 GUID 路径写入启动分区，不主动分配资源管理器盘符。
    $esp = Get-Partition -DiskNumber $espDisk.Number -PartitionNumber $esp.PartitionNumber
    if ($esp.DriveLetter) { throw 'A drive letter was unexpectedly assigned to the boot partition.' }
    $espVolume = Get-Volume -Partition $esp -ErrorAction Stop
    $espRoot = [string]$espVolume.Path
    if ([string]::IsNullOrWhiteSpace($espRoot) -or -not [IO.Directory]::Exists($espRoot)) { throw 'Boot partition volume GUID path unavailable.' }
    Verify-Disk $storeDisk ($storeBytes + 32MB)
    Write-Host '  Creating backup partition...' -ForegroundColor Gray
    $store = New-Partition -DiskNumber $storeDisk.Number -Size $storeBytes
    Set-Partition -DiskNumber $storeDisk.Number -PartitionNumber $store.PartitionNumber -NoDefaultDriveLetter $true -Confirm:$false -ErrorAction Stop
    $store = Get-Partition -DiskNumber $storeDisk.Number -PartitionNumber $store.PartitionNumber
    Format-Volume -Partition $store -FileSystem exFAT -NewFileSystemLabel BACKUP_OS -Confirm:$false -Force | Out-Null
    $store = Get-Partition -DiskNumber $storeDisk.Number -PartitionNumber $store.PartitionNumber
    $storeVolume = Get-Volume -Partition $store -ErrorAction Stop
    $storeRoot = [string]$storeVolume.Path
    if ([string]::IsNullOrWhiteSpace($storeRoot)) { throw 'Backup partition formatted, but its volume GUID path is unavailable.' }
    [IO.Directory]::CreateDirectory([IO.Path]::Combine($storeRoot, 'partimag')) | Out-Null
    # 卷 GUID 路径无需资源管理器盘符，也不需要设置会影响访问的 IsHidden 属性。
    Write-Host '  Writing boot files...' -ForegroundColor Gray
    $dest = [IO.Path]::Combine($espRoot, 'EFI\clonezilla')
    $bootLive = [IO.Path]::Combine($dest, 'live')
    $mediaLive = [IO.Path]::Combine($espRoot, 'live')
    [IO.Directory]::CreateDirectory($bootLive) | Out-Null
    # Clonezilla 在介质根目录 live/ 查找 squashfs。
    [IO.Directory]::CreateDirectory($mediaLive) | Out-Null
    foreach ($name in @('vmlinuz','initrd.img')) { [IO.File]::Copy((Join-Path $Project "resources\live\$name"), [IO.Path]::Combine($bootLive, $name), $false) }
    [IO.File]::Copy((Join-Path $Project 'resources\live\filesystem.squashfs'), [IO.Path]::Combine($mediaLive, 'filesystem.squashfs'), $false)
    foreach ($name in @('grubx64.efi','start.sh','recovery-runtime.sh')) { [IO.File]::Copy((Join-Path $Project "assets\$name"), [IO.Path]::Combine($dest, $name), $false) }
    $conf = @("system_ptuuid=$systemGuid", $identityLine, "store_partuuid=$(([string]$store.Guid).Trim('{}').ToLowerInvariant())", "partuuid=$(([string]$windows.Guid).Trim('{}').ToLowerInvariant())") -join "`n"
    [IO.File]::WriteAllText(([IO.Path]::Combine($dest, 'recovery.conf')), $conf + "`n", [Text.Encoding]::ASCII)
    $grub = @'
insmod part_gpt
insmod fat
insmod ntfs
insmod search_fs_file
insmod chain
insmod lsefi
insmod test
set default=0
set timeout_style=menu
set timeout=-1
set have_windows=0
search --file --set=cz /EFI/clonezilla/recovery.conf
# Enumerate firmware entries in BootOrder, with Windows entries first.
scan_uefi_boot reset
while scan_uefi_boot windows; do
    set have_windows=1
    menuentry "$detected_boot_name" "$detected_boot_device" "$detected_boot_path" {
        set root="$2"
        chainloader "$3"
    }
done
scan_uefi_boot reset
while scan_uefi_boot other; do
    menuentry "$detected_boot_name" "$detected_boot_device" "$detected_boot_path" {
        set root="$2"
        chainloader "$3"
    }
done
if [ "$have_windows" = "1" ]; then
    set timeout=2
else
    echo 'No uniquely identifiable Windows UEFI boot entry; automatic boot disabled.'
fi
menuentry 'Recovery OS' {
    linux ($cz)/EFI/clonezilla/live/vmlinuz boot=live union=overlay username=user config components noswap nomodeset noeject live-media-path=/live locales=en_US.UTF-8 keyboard-layouts=us ocs_live_batch=yes ocs_live_run="sudo bash /run/live/medium/EFI/clonezilla/start.sh recover"
    initrd ($cz)/EFI/clonezilla/live/initrd.img
}
menuentry 'Backup OS' {
    linux ($cz)/EFI/clonezilla/live/vmlinuz boot=live union=overlay username=user config components noswap nomodeset noeject live-media-path=/live locales=en_US.UTF-8 keyboard-layouts=us ocs_live_batch=yes ocs_live_run="sudo bash /run/live/medium/EFI/clonezilla/start.sh backup"
    initrd ($cz)/EFI/clonezilla/live/initrd.img
}
'@
    [IO.File]::WriteAllText(([IO.Path]::Combine($dest, 'grub.cfg')), ($grub -replace "`r`n", "`n"), [Text.Encoding]::ASCII)
    $esp = Get-Partition -DiskNumber $espDisk.Number -PartitionNumber $esp.PartitionNumber
    if ((Get-Disk -Number $espDisk.Number).UniqueId -ne $espDisk.UniqueId) { throw 'Disk identity changed.' }
    $sectorSize = [uint64](Get-Disk -Number $espDisk.Number).LogicalSectorSize
    if ($sectorSize -eq 0 -or ($esp.Offset % $sectorSize) -ne 0 -or ($esp.Size % $sectorSize) -ne 0) { throw 'Invalid partition sector information.' }
    $partitionGuid = ([string]$esp.Guid).Trim('{}')
    $partNumber = $esp.PartitionNumber
    $startLba = [uint64]($esp.Offset / $sectorSize)
    $sizeLba = [uint64]($esp.Size / $sectorSize)
    Set-Partition -DiskNumber $espDisk.Number -PartitionNumber $partNumber -GptType $EspType -Confirm:$false
    Write-Host '  Registering boot entry...' -ForegroundColor Gray
    & (Join-Path $Project 'FirmwareHelper.exe') $partitionGuid $partNumber $startLba $sizeLba
    if ($LASTEXITCODE -ne 0) { throw 'UEFI registration failed; partitions and files remain. Inspect them manually.' }
    Write-Host "`n  Deployment complete" -ForegroundColor Green
    Write-Host '  Restart and use the boot menu to back up or recover.'
} catch {
    $code = Get-ProductErrorCode $_.Exception.Message
    Log-Detail $code ($_.Exception.ToString())
    Write-Host ("`n  Error: " + $code) -ForegroundColor Red
    if ($script:DiskChangesStarted) { Write-Warning 'Disk operations may be partially complete; inspect the log before proceeding.' }
    $ExitCode = 1
}
finally {
    if ($TranscriptStarted) { Stop-Transcript | Out-Null }
}
exit $ExitCode
