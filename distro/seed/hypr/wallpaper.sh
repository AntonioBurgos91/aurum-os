#!/usr/bin/env bash
# ==============================================================================
# AurumOS wallpaper engine
#
# Picks one of three modes, in priority order:
#   1. swww (animated, multi-monitor, transitions)  — preferred
#   2. swaybg (static, single image)                 — fallback
#   3. solid color via swaybg                        — last resort
#
# Honors:
#   $AURUM_WALLPAPER          single image override (any mode)
#   $AURUM_WALLPAPER_DIR      directory to rotate through (swww mode only)
#   $AURUM_WALLPAPER_INTERVAL rotation interval in seconds (default 1800)
# ==============================================================================

set -euo pipefail

WALLPAPER_DIR_DEFAULT="/usr/share/backgrounds/aurumos"
USER_WALLPAPER_DIR="${HOME}/Pictures/Wallpapers"
FALLBACK_COLOR="#1E1E24"

# Resolve target directory: explicit env > user dir > system dir.
if [[ -n "${AURUM_WALLPAPER_DIR:-}" ]]; then
    WALLPAPER_DIR="${AURUM_WALLPAPER_DIR}"
elif [[ -d "${USER_WALLPAPER_DIR}" && -n "$(ls -A "${USER_WALLPAPER_DIR}" 2>/dev/null)" ]]; then
    WALLPAPER_DIR="${USER_WALLPAPER_DIR}"
else
    WALLPAPER_DIR="${WALLPAPER_DIR_DEFAULT}"
fi

DEFAULT_WALLPAPER="${WALLPAPER_DIR}/default.jpg"
INTERVAL="${AURUM_WALLPAPER_INTERVAL:-1800}"

log()  { echo "[wallpaper] $*"; }
warn() { echo "[wallpaper] $*" >&2; }

# Pick a wallpaper file: explicit env > default.jpg in dir > random pick.
pick_wallpaper() {
    if [[ -n "${AURUM_WALLPAPER:-}" && -f "${AURUM_WALLPAPER}" ]]; then
        echo "${AURUM_WALLPAPER}"
        return 0
    fi
    if [[ -f "${DEFAULT_WALLPAPER}" ]]; then
        echo "${DEFAULT_WALLPAPER}"
        return 0
    fi
    # Anything in the directory. We don't trust globs here because the dir
    # may be missing entirely on a freshly installed system.
    if [[ -d "${WALLPAPER_DIR}" ]]; then
        local pick
        pick="$(find "${WALLPAPER_DIR}" -maxdepth 2 -type f \
                  \( -iname '*.jpg' -o -iname '*.jpeg' -o -iname '*.png' -o -iname '*.webp' \) \
                  2>/dev/null | shuf -n 1)"
        if [[ -n "${pick}" ]]; then
            echo "${pick}"
            return 0
        fi
    fi
    return 1
}

# --- Mode 1: swww (preferred) ---------------------------------------------
run_swww() {
    if ! command -v swww >/dev/null 2>&1; then
        return 1
    fi
    log "using swww"
    # swww-daemon must be running before `swww img` can take effect. It exits
    # immediately if already started, so this is safe to call unconditionally.
    swww-daemon --format xrgb &>/dev/null &
    # Wait until the socket is ready before we send commands.
    swww query &>/dev/null || sleep 0.5

    local initial
    if initial="$(pick_wallpaper)"; then
        swww img "${initial}" \
            --transition-type grow \
            --transition-pos center \
            --transition-duration 1.5 \
            --transition-fps 60
    else
        warn "no wallpaper file found; swww-daemon left idle"
    fi

    # Optional rotation. Only spin a rotation loop when (a) we have a real
    # directory to rotate through and (b) the user hasn't pinned a single
    # image. Background-detach so this script can be exec-once'd.
    if [[ -z "${AURUM_WALLPAPER:-}" && -d "${WALLPAPER_DIR}" ]]; then
        local count
        count="$(find "${WALLPAPER_DIR}" -maxdepth 2 -type f \
                  \( -iname '*.jpg' -o -iname '*.jpeg' -o -iname '*.png' -o -iname '*.webp' \) \
                  | wc -l)"
        if (( count > 1 )); then
            (
                while sleep "${INTERVAL}"; do
                    local next
                    next="$(pick_wallpaper)" || continue
                    swww img "${next}" \
                        --transition-type fade \
                        --transition-duration 2 \
                        --transition-fps 60 \
                        --transition-step 90 || true
                done
            ) &
            disown
        fi
    fi
    return 0
}

# --- Mode 2: swaybg static -------------------------------------------------
run_swaybg() {
    if ! command -v swaybg >/dev/null 2>&1; then
        return 1
    fi
    log "using swaybg (no swww available)"
    killall -q swaybg || true
    local pick
    if pick="$(pick_wallpaper)"; then
        exec swaybg -i "${pick}" -m fit
    else
        warn "no wallpaper file found; falling back to solid color ${FALLBACK_COLOR}"
        exec swaybg -c "${FALLBACK_COLOR}"
    fi
}

main() {
    if run_swww; then
        return 0
    fi
    run_swaybg
}

main "$@"
