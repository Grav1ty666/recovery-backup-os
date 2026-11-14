#!/usr/bin/env bash
set -Eeuo pipefail
ROOT=/run/live/medium/EFI/clonezilla
action=${1:-}
case "$action" in backup|recover|baseline) ;; *) echo 'Invalid action'; exit 1 ;; esac
export RECOVERY_CONFIG="$ROOT/recovery.conf"
exec bash "$ROOT/recovery-runtime.sh" "$action"
