#!/usr/bin/env bash
# Clonezilla 运行组件；部分功能尚未完成端到端验证。
# 配置格式见 recovery.conf.example；不执行 shell 格式的配置文件。
set -Eeuo pipefail
export LC_ALL=C
umask 077

CONFIG=${RECOVERY_CONFIG:-/run/recovery/recovery.conf}
MOUNT_ROOT=${RECOVERY_MOUNT_ROOT:-/run/recovery/store}
IMAGE_ROOT=/home/partimag
PARTS=()
STORE_UUID=
STORE_PARTUUID=
STORE_MODE=dedicated
STORE_MODE_SEEN=0
STORE_TOKEN=
REPOSITORY_ROOT=
SYSTEM_PTUUID=
EXPECTED_SERIAL=
IDENTITY_MODE=serial
STORE_MOUNTED=0
IMAGE_MOUNTED=0
SOURCE_CHECK=/run/recovery/source-check
SOURCE_MOUNTED=0

fail() { printf 'ERROR: %s\n' "$*" >&2; exit 1; }
read_config() {
    [[ -f $CONFIG && ! -L $CONFIG ]] || fail 'Configuration file missing or is a symbolic link.'
    local key value
    while IFS='=' read -r key value || [[ -n $key$value ]]; do
        case "$key" in
            ''|\#*) continue ;;
            store_uuid) [[ -z $STORE_UUID && $value =~ ^[[:alnum:]-]+$ ]] || fail 'Invalid or duplicate store UUID.'; STORE_UUID=$value ;;
            store_partuuid) [[ -z $STORE_PARTUUID && $value =~ ^[[:xdigit:]-]+$ ]] || fail 'Invalid or duplicate store PARTUUID.'; STORE_PARTUUID=$value ;;
            store_mode) [[ $STORE_MODE_SEEN == 0 && ( $value == existing || $value == visible ) ]] || fail 'Invalid or duplicate store mode.'; STORE_MODE=$value; STORE_MODE_SEEN=1 ;;
            store_token) [[ -z $STORE_TOKEN && $value =~ ^[0-9a-f]{32}$ ]] || fail 'Invalid or duplicate store token.'; STORE_TOKEN=$value ;;
            system_ptuuid) [[ -z $SYSTEM_PTUUID && $value =~ ^[[:xdigit:]-]+$ ]] || fail 'Invalid or duplicate system disk GUID.'; SYSTEM_PTUUID=$value ;;
            system_serial) [[ -z $EXPECTED_SERIAL && $value =~ ^[[:alnum:]_.:-]+$ ]] || fail 'Invalid or duplicate disk serial.'; EXPECTED_SERIAL=$value ;;
            identity_mode) [[ $value == ptuuid_only ]] || fail 'Unsupported identity mode.'; IDENTITY_MODE=$value ;;
            partuuid) [[ $value =~ ^[[:xdigit:]-]+$ ]] || fail 'Invalid partition GUID.'; PARTS+=("$value") ;;
            *) fail "Unknown configuration key: $key" ;;
        esac
    done < "$CONFIG"
    [[ ( -n $STORE_UUID || -n $STORE_PARTUUID ) && -n $SYSTEM_PTUUID && ${#PARTS[@]} -gt 0 ]] || fail 'Required configuration is missing.'
    [[ $IDENTITY_MODE == ptuuid_only || -n $EXPECTED_SERIAL ]] || fail 'Disk serial is missing.'
    [[ $IDENTITY_MODE != ptuuid_only || -z $EXPECTED_SERIAL ]] || fail 'Inconsistent serial-free configuration.'
    [[ -z $STORE_UUID || -z $STORE_PARTUUID ]] || fail 'Store must use only one identifier.'
    if [[ $STORE_MODE == existing ]]; then [[ -n $STORE_PARTUUID && -n $STORE_TOKEN ]] || fail 'Existing store identity missing.'; else [[ -z $STORE_TOKEN ]] || fail 'Unexpected store token.'; fi
}
unique_device() {
    local kind=$1 value=$2
    local -a found=()
    mapfile -t found < <(blkid -t "$kind=$value" -o device | sort -u)
    ((${#found[@]} == 1)) || fail "$kind=$value not found or not unique."
    readlink -f -- "${found[0]}"
}
unique_system_disk() {
    local path type value
    local -a found=()
    while read -r path type; do
        [[ $type == disk ]] || continue
        value=$(blkid -p -s PTUUID -o value "$path" 2>/dev/null || true)
        [[ ${value,,} == "${SYSTEM_PTUUID,,}" ]] && found+=("$(readlink -f "$path")")
    done < <(lsblk -dnpo NAME,TYPE)
    ((${#found[@]} == 1)) || fail 'System disk GPT identifier not found or not unique.'
    printf '%s\n' "${found[0]}"
}
resolve_devices() {
    SYSTEM=$(unique_system_disk)
    [[ $(lsblk -dnro TYPE "$SYSTEM") == disk ]] || fail 'System target is not a disk.'
    local actual_serial
    if [[ $IDENTITY_MODE == serial ]]; then
        actual_serial=$(lsblk -dnro SERIAL "$SYSTEM" | xargs)
        # Windows and Linux can report different serial formats for the same disk.
        # Disk GPT uniqueness is already checked; each target PARTUUID and parent
        # disk is validated below before any backup or restore is allowed.
        if [[ -z $actual_serial || $actual_serial != "$EXPECTED_SERIAL" ]]; then
            printf '%s\n' 'WARNING: Disk serial differs or is unavailable; verifying the unique disk and partition GUIDs instead.'
        fi
    else
        printf '%s\n' 'WARNING: No usable disk serial; identifying target by disk and partition GUID only.'
    fi
    if [[ -n $STORE_PARTUUID ]]; then STORE=$(unique_device PARTUUID "$STORE_PARTUUID"); else STORE=$(unique_device UUID "$STORE_UUID"); fi
    STORE_FS=$(blkid -s TYPE -o value "$STORE")
    if [[ $STORE_MODE == dedicated || $STORE_MODE == visible ]]; then
        [[ $(blkid -s LABEL -o value "$STORE") == BACKUP_OS && $STORE_FS == exfat ]] || fail 'Dedicated store identity or filesystem does not match.'
    else
        [[ $STORE_FS == ntfs || $STORE_FS == exfat ]] || fail 'Existing store filesystem unsupported.'
    fi
    local guid part parent existing
    DEVICES=()
    for guid in "${PARTS[@]}"; do
        part=$(unique_device PARTUUID "$guid")
        [[ $(lsblk -dnro TYPE "$part") == part ]] || fail 'Selected target is not a partition.'
        parent=$(lsblk -dnro PKNAME "$part")
        [[ -n $parent && $(readlink -f "/dev/$parent") == "$SYSTEM" ]] || fail 'Target partition is not on the configured system disk.'
        [[ $part != "$STORE" ]] || fail 'Image store cannot be a restore target.'
        for existing in "${DEVICES[@]}"; do [[ $existing != "$part" ]] || fail 'Duplicate target partition.'; done
        [[ -z $(findmnt -rn -S "$part" -o TARGET) ]] || fail "Target partition is mounted: $part"
        DEVICES+=("$part")
    done
}
mount_repository() {
    [[ -z $(findmnt -rn -S "$STORE" -o TARGET) ]] || fail 'Image store is already mounted.'
    mkdir -p "$MOUNT_ROOT" "$IMAGE_ROOT"
    mountpoint -q "$MOUNT_ROOT" && fail 'Store mount point is already in use.'
    mountpoint -q "$IMAGE_ROOT" && fail 'Image mount point is already in use.'
    if [[ $STORE_FS == ntfs ]]; then
        command -v ntfs-3g >/dev/null || fail 'ntfs-3g is unavailable.'
        mount -t ntfs-3g -o rw,nosuid,nodev "$STORE" "$MOUNT_ROOT" || fail 'NTFS store could not be safely mounted; shut down Windows fully and check the volume.'
    else
        mount -t exfat -o rw,nosuid,nodev "$STORE" "$MOUNT_ROOT"
    fi
    STORE_MOUNTED=1
    if [[ $STORE_MODE == existing ]]; then
        REPOSITORY_ROOT="$MOUNT_ROOT/RecoveryBackupOS"
        [[ -d $REPOSITORY_ROOT && ! -L $REPOSITORY_ROOT && -f $REPOSITORY_ROOT/.recovery-backup-os-owner && ! -L $REPOSITORY_ROOT/.recovery-backup-os-owner ]] || fail 'Owned storage directory missing or unsafe.'
        [[ $(cat "$REPOSITORY_ROOT/.recovery-backup-os-owner") == "$STORE_TOKEN" ]] || fail 'Storage ownership marker mismatch.'
    else REPOSITORY_ROOT=$MOUNT_ROOT; fi
    [[ ! -L $REPOSITORY_ROOT/partimag ]] || fail 'Image directory must not be a symbolic link.'
    mkdir -p "$REPOSITORY_ROOT/partimag"
    mount --bind "$REPOSITORY_ROOT/partimag" "$IMAGE_ROOT"
    IMAGE_MOUNTED=1
}
cleanup() {
    if (( SOURCE_MOUNTED )); then umount "$SOURCE_CHECK" || true; SOURCE_MOUNTED=0; fi
    if (( IMAGE_MOUNTED )); then umount "$IMAGE_ROOT" || true; IMAGE_MOUNTED=0; fi
    if (( STORE_MOUNTED )); then umount "$MOUNT_ROOT" || true; STORE_MOUNTED=0; fi
}
# 先写入 Live 内存日志；仓库可访问时，在卸载前另存到 BACKUP_OS/recovery_logs。
finalize_session() {
    local status=$1
    trap - EXIT
    if (( status == 0 )); then printf '%s\n' 'Task status: completed.'; else printf 'Task status: FAILED or ABORTED (exit %s); inspect the log.\n' "$status"; fi
    exec 1>&3 2>&4
    wait "$LOGGER_PID" || true
    if (( STORE_MOUNTED )) && [[ -n $REPOSITORY_ROOT && -d $REPOSITORY_ROOT && ! -L $REPOSITORY_ROOT ]]; then
        mkdir -p "$REPOSITORY_ROOT/recovery_logs" || true
        cp -- "$SESSION_LOG" "$REPOSITORY_ROOT/recovery_logs/" || printf '%s\n' 'Could not save the recovery log to the image store.' >&2
        sync
    fi
    cleanup
}
# 基准与历史备份在同一仓库内；只进行目录重命名，不复制、不覆盖。
promote_to_baseline() {
    local original=$1 target="$IMAGE_ROOT/BACKUP_OS"
    [[ $original != BACKUP_OS && -d $IMAGE_ROOT/$original && ! -L $IMAGE_ROOT/$original ]] || fail 'Backup directory is invalid.'
    [[ ! -e $target && ! -L $target && ! -e $IMAGE_ROOT/.BACKUP_OS.incomplete ]] || fail 'BACKUP_OS or an incomplete marker already exists; refusing to overwrite.'
    mv -T -n -- "$IMAGE_ROOT/$original" "$target" || fail 'Could not set BACKUP_OS.'
    [[ -d $target && ! -L $target && ! -e $IMAGE_ROOT/$original ]] || fail 'Setting BACKUP_OS did not complete; inspect the store.'
    printf '%s is now the fixed baseline BACKUP_OS.\n' "$original"
}
main() {
    [[ $EUID -eq 0 ]] || fail 'Root privileges are required.'
    case ${1:-} in baseline|backup|recover) ;; *) fail 'Action must be baseline, backup, or recover.' ;; esac
    for cmd in blkid lsblk findmnt mount mountpoint ocs-sr; do command -v "$cmd" >/dev/null || fail "Missing command: $cmd"; done
    if [[ $1 == recover ]]; then command -v ocs-chkimg >/dev/null || fail 'Missing image check command: ocs-chkimg'; fi
    mkdir -p /run/recovery
    SESSION_LOG=$(mktemp "/run/recovery/${1}_$(date +%Y%m%d_%H%M%S)_XXXXXX.log")
    exec 3>&1 4>&2
    exec > >(tee -a "$SESSION_LOG") 2>&1
    LOGGER_PID=$!
    trap 'finalize_session $?' EXIT
    printf 'Task: %s; temporary log: %s\n' "$1" "$SESSION_LOG"
    read_config
    resolve_devices
    mount_repository
    local action=$1 image
    case "$action" in
        baseline) image=BACKUP_OS ;;
        backup) image="auto_backup_$(date +%Y%m%d_%H%M%S)" ;;
        recover) image=BACKUP_OS ;;
    esac
    printf 'System disk: %s\nTarget partition: %s\nImage store: %s\nImage: %s\n' "$SYSTEM" "${DEVICES[*]}" "$STORE" "$image"
    if [[ $action == recover ]]; then
        if [[ ! -d $IMAGE_ROOT/BACKUP_OS || -L $IMAGE_ROOT/BACKUP_OS ]]; then
            printf '%s\n' 'BACKUP_OS image directory not found. Restore aborted. Rebooting in 3 seconds.'
            sync
            finalize_session 2
            sleep 3
            if ! reboot; then printf '%s\n' 'Automatic reboot failed. Please reboot manually.' >&2; return 1; fi
            return 0
        fi
        [[ ! -e $IMAGE_ROOT/.BACKUP_OS.incomplete ]] || fail 'BACKUP_OS has an incomplete marker; refusing to restore.'
        [[ ! -e $IMAGE_ROOT/.$image.incomplete ]] || fail 'Image has an incomplete marker; refusing to restore.'
        printf 'Checking image directory: %s\n' "$image"
        [[ -f $IMAGE_ROOT/$image/parts && ! -L $IMAGE_ROOT/$image/parts ]] || fail 'Baseline image is missing the partition list.'
        local -a saved_parts=() current_parts=()
        read -r -a saved_parts < "$IMAGE_ROOT/$image/parts"
        for part in "${DEVICES[@]}"; do current_parts+=("${part##*/}"); done
        [[ ${saved_parts[*]} == "${current_parts[*]}" ]] || fail 'Image partition names do not match the current devices; restore refused.'
        ocs-chkimg --batch --ocsroot "$IMAGE_ROOT" "$image" || fail 'Image verification failed.'
        printf 'Restore will now automatically overwrite the target partition.\n'
        ocs-sr --batch -k -p true restoreparts "$image" "${DEVICES[*]}"
    else
        [[ ! -e $IMAGE_ROOT/$image ]] || fail 'Image name already exists.'
        # 展示 NTFS 已用空间和目标可用空间，不以虚构压缩率强制拒绝备份。
        local used=0 part_used available marker
        mkdir -p "$SOURCE_CHECK"
        mountpoint -q "$SOURCE_CHECK" && fail 'Source check mount point is already in use.'
        for part in "${DEVICES[@]}"; do
            [[ $(blkid -s TYPE -o value "$part") == ntfs ]] || fail 'Used-space calculation currently supports NTFS only.'
            mount -t ntfs-3g -o ro,norecover "$part" "$SOURCE_CHECK" || fail 'Could not mount source read-only to calculate used space.'
            SOURCE_MOUNTED=1
            part_used=$(df -PB1 "$SOURCE_CHECK" | awk 'NR==2 {print $3}')
            [[ $part_used =~ ^[0-9]+$ ]] || fail 'Could not calculate used source space.'
            umount "$SOURCE_CHECK" || fail 'Could not unmount source partition; backup refused.'
            SOURCE_MOUNTED=0
            used=$((used + part_used))
        done
        available=$(df -PB1 "$IMAGE_ROOT" | awk 'NR==2 {print $4}')
        printf 'Source bytes used: %s; store bytes available: %s. Compressed image size cannot be guaranteed.\n' "$used" "$available"
        if [[ ! $available =~ ^[0-9]+$ || $available -le 0 ]]; then
            printf '%s\n' 'ERROR: No usable space in the image store. Backup aborted; rebooting in 5 seconds.'
            sync
            finalize_session 1
            sleep 5
            if ! reboot; then printf '%s\n' 'Automatic reboot failed. Please reboot manually.' >&2; fi
            exit 1
        fi
        marker="$IMAGE_ROOT/.${image}.incomplete"
        [[ ! -e $marker ]] || fail 'An incomplete marker already exists; inspect it first.'
        printf 'Incomplete: removed only after the backup command succeeds. Post-backup image verification is disabled.\n' > "$marker"
        if ocs-sr --batch -scs -q2 -z1p -p true saveparts "$image" "${DEVICES[*]}"; then
            rm -f -- "$marker"
        else
            backup_status=$?
            printf 'ERROR: Backup failed (exit %s). Storage may be insufficient; inspect the log. The incomplete marker was retained. Rebooting in 5 seconds.\n' "$backup_status"
            sync
            finalize_session "$backup_status"
            sleep 5
            if ! reboot; then printf '%s\n' 'Automatic reboot failed. Please reboot manually.' >&2; fi
            exit "$backup_status"
        fi
        printf '%s\n' 'Backup command completed; post-backup image verification is disabled.'
        # 首次成功备份自动成为基准；现有基准或未完成标记存在时绝不覆盖。
        if [[ $action == backup && ! -e $IMAGE_ROOT/BACKUP_OS && ! -L $IMAGE_ROOT/BACKUP_OS && ! -e $IMAGE_ROOT/.BACKUP_OS.incomplete ]]; then
            promote_to_baseline "$image"
        fi
    fi
    sync
    printf '%s\n' 'Operation completed. Rebooting.'
    finalize_session 0
    if ! reboot; then printf '%s\n' 'Automatic reboot failed. Please reboot manually.' >&2; return 1; fi
}
main "$@"
