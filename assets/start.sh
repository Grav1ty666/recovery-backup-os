#!/usr/bin/env bash
set -Eeuo pipefail
ROOT=/run/live/medium/EFI/clonezilla
action=${1:-}
case "$action" in backup|recover|baseline) ;; *) echo 'Invalid action'; exit 1 ;; esac
export RECOVERY_CONFIG="$ROOT/recovery.conf"
export RECOVERY_ACTION="$action"
# Reserve one terminal row so full-screen Clonezilla/Partclone cannot overwrite
# the attribution. Keep a direct fallback for non-interactive environments.
if [[ -t 0 && -t 1 ]] && command -v tmux >/dev/null 2>&1 && [[ -z ${TMUX:-} ]]; then
    mkdir -p /run/recovery
    config=$(mktemp /run/recovery/tmux-attribution.XXXXXX)
    cat > "$config" <<'EOF'
set-option -g status 1
set-option -g status-position bottom
set-option -g status-style 'fg=colour245,bg=black'
set-option -g status-format[0] '#[align=centre]Website: backup.mali040929.dpdns.org'
set-option -g status-interval 0
EOF
    # Run the unchanged workflow in its own pane after reading the config.
    exec tmux -L "recovery-attribution-$$" -f "$config" new-session -s recovery 'exec bash /run/live/medium/EFI/clonezilla/recovery-runtime.sh "$RECOVERY_ACTION"'
fi
exec bash "$ROOT/recovery-runtime.sh" "$action"
