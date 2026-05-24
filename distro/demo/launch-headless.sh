#!/usr/bin/env bash
# AurumOS desktop preview launcher.
#
# Pipeline:
#   D-Bus → Rust daemons → Hyprland (DRM or headless) → swaybg backdrop
#   → workspace pinned to VIRTUAL-1 → Qt6 desktop apps → wayvnc capture
#   → websockify+noVNC at :6080.
#
# Backend modes (env GPU_BACKEND, default drm):
#   drm        — real NVIDIA / AMD / Intel EGL via /dev/dri passthrough.
#   headless   — pure-software wlroots backend + pixman renderer + swrast Mesa.
#                Used when the container has no GPU device exposed.

set -uo pipefail

# ── utility helpers ──────────────────────────────────────────────────────────
log()  { echo "[launch] $*"; }
die()  { echo "[launch] FATAL: $*" >&2; exit 1; }
wait_sock() {
    local sock="$1" timeout="${2:-60}" pid="${3:-0}"
    for _ in $(seq 1 $((timeout*2))); do
        [[ -S "$sock" ]] && return 0
        if [[ $pid -gt 0 ]] && ! kill -0 "$pid" 2>/dev/null; then
            log "Proceso $pid murió esperando $sock"
            return 1
        fi
        sleep 0.5
    done
    return 1
}

# ── runtime dirs ──────────────────────────────────────────────────────────────
export XDG_RUNTIME_DIR="${XDG_RUNTIME_DIR:-/tmp/runtime}"
mkdir -p "${XDG_RUNTIME_DIR}"             || die "Failed to create ${XDG_RUNTIME_DIR}"
mkdir -p /var/log/aurum                    || die "Failed to create /var/log/aurum"
mkdir -p /home/developer/.cache/hyprland   || die "Failed to create /home/developer/.cache/hyprland"
chmod 0700 "${XDG_RUNTIME_DIR}"
chmod 0700 /home/developer/.cache/hyprland

# ── per-backend env ──────────────────────────────────────────────────────────
case "${GPU_BACKEND:-drm}" in
    drm)
        log "Backend: drm (real EGL via /dev/dri passthrough)"
        # Do NOT set WLR_RENDERER / MESA_LOADER_DRIVER_OVERRIDE — let EGL pick
        # the NVIDIA / radeonsi / iris driver natively.
        ;;
    headless)
        log "Backend: headless (pixman + swrast software rendering)"
        export WLR_BACKENDS=headless
        export WLR_RENDERER=pixman
        export LIBGL_ALWAYS_SOFTWARE=1
        export MESA_LOADER_DRIVER_OVERRIDE=kms_swrast
        ;;
    *)
        die "Unknown GPU_BACKEND='${GPU_BACKEND}' (use drm|headless)"
        ;;
esac

# Shared env regardless of backend.
export LIBSEAT_BACKEND=noop
export WLR_NO_HARDWARE_CURSORS=1
export WLR_LIBINPUT_NO_DEVICES=1
export AQ_NO_MODIFIERS=1
export WAYLAND_DISPLAY=wayland-1
export NVIDIA_DRIVER_CAPABILITIES=all

# ── D-Bus session bus ────────────────────────────────────────────────────────
log "Arrancando D-Bus session..."
rm -f "${XDG_RUNTIME_DIR}/dbus-session.addr" "${XDG_RUNTIME_DIR}/dbus-session.sock"
dbus-daemon --session --print-address --fork \
    --address="unix:path=${XDG_RUNTIME_DIR}/dbus-session.sock" \
    > "${XDG_RUNTIME_DIR}/dbus-session.addr" 2>/dev/null || true
for _ in $(seq 1 20); do
    [[ -s "${XDG_RUNTIME_DIR}/dbus-session.addr" ]] && break
    [[ -S "${XDG_RUNTIME_DIR}/dbus-session.sock" ]] && \
        echo "unix:path=${XDG_RUNTIME_DIR}/dbus-session.sock" \
        > "${XDG_RUNTIME_DIR}/dbus-session.addr" && break
    sleep 0.3
done
export DBUS_SESSION_BUS_ADDRESS="$(cat "${XDG_RUNTIME_DIR}/dbus-session.addr" 2>/dev/null \
    || echo "unix:path=${XDG_RUNTIME_DIR}/dbus-session.sock")"
log "D-Bus: ${DBUS_SESSION_BUS_ADDRESS}"

# ── Rust daemons ──────────────────────────────────────────────────────────────
# Each daemon runs under a tiny bash supervisor: if the process exits non-zero
# we restart it after a short cool-down so the desktop's GPU/Spotlight/ML
# panels stay live. We cap at 5 restarts per minute to avoid CPU pegging on a
# genuinely broken daemon; once the budget is exhausted we leave the slot
# down and let the smoke-test surface the failure (production install will
# use systemd-user units with the same intent).
#
# `setsid` detaches each supervisor from this script's process group so a
# subsequent Hyprland exit doesn't cascade-kill the daemons.
supervise() {
    local name=$1 log=$2
    (
        # pipefail so $? reflects the daemon's exit, not sed's (sed always
        # returns 0 once the daemon closes its stdout). Without this we'd
        # never detect a crashed daemon and never count restarts.
        set -o pipefail
        local count=0
        local window_start=$(date +%s)
        while true; do
            if ! command -v "$name" >/dev/null 2>&1; then
                echo "[$name supervisor] binary not found in PATH, giving up" >>"$log"
                return 2
            fi
            "$name" 2>&1 | sed "s|^|[$name] |" >>"$log"
            local rc=$?
            local now=$(date +%s)
            if (( now - window_start >= 60 )); then
                count=0; window_start=$now
            fi
            count=$((count + 1))
            if (( count >= 5 )); then
                echo "[$name supervisor] crashed $count× in <60s (last rc=$rc) — giving up." >>"$log"
                return 1
            fi
            sleep 1
        done
    ) &
    disown
}
log "Arrancando daemons Rust con supervisor..."
RUST_LOG=warn supervise aurum-gpu-monitor       /var/log/aurum/gpu.log
RUST_LOG=warn supervise aurum-spotlight-indexer /var/log/aurum/spi.log
RUST_LOG=warn supervise aurum-ml-jobs-tracker   /var/log/aurum/mlt.log
sleep 1

# ── Hyprland ──────────────────────────────────────────────────────────────────
log "Arrancando Hyprland..."
Hyprland --config /etc/aurum/hypr/preview.conf >/var/log/aurum/hypr.log 2>&1 &
HYPR_PID=$!
wait_sock "${XDG_RUNTIME_DIR}/${WAYLAND_DISPLAY}" 60 $HYPR_PID \
    || { log "Hyprland log tail:"; tail -25 /var/log/aurum/hypr.log >&2; die "Hyprland socket never appeared"; }
log "Hyprland socket OK ✓"

# Hyprland's IPC env var (lets hyprctl find this instance from any subshell).
sleep 1
HYPRLAND_INSTANCE_SIGNATURE="$(ls -t "${XDG_RUNTIME_DIR}/hypr/" 2>/dev/null | head -1)"
export HYPRLAND_INSTANCE_SIGNATURE
log "Hyprland IPC signature: ${HYPRLAND_INSTANCE_SIGNATURE}"

# ── Virtual monitor + workspace ──────────────────────────────────────────────
hyprctl output create headless VIRTUAL-1 >/dev/null 2>&1 && log "VIRTUAL-1 created" \
    || log "VIRTUAL-1 already exists (or output create not needed)"
sleep 1
hyprctl dispatch moveworkspacetomonitor 1 VIRTUAL-1 >/dev/null 2>&1 || true
hyprctl dispatch focusmonitor VIRTUAL-1            >/dev/null 2>&1 || true

# ── Backdrop wallpaper (so gaps between windows show macOS dark) ─────────────
# The Qt apps now use opaque AARRGGBB colors ("#FF1c1c1e") on their Window
# roots, so they no longer need a backdrop to hide alpha=0 pixels. swaybg is
# still useful: it paints the same macOS dark color over the parts of the
# virtual output not covered by any app (e.g., between the menubar and the
# floating finder), so the desktop reads as a unified dark surface rather
# than wlroots' default checkerboard.
log "Spawning swaybg backdrop (Aurum Sequoia Dark wallpaper)..."
# Default wallpaper installed by distro/assets/install-assets.sh as a symlink
# pointing at the currently-active rendered Sequoia Dark image. If the asset
# is missing for any reason fall back to a solid Theme.windowBg color so the
# desktop is never naked.
WALLPAPER=/usr/share/aurum-os/wallpapers/default.png
if [ -r "$WALLPAPER" ]; then
    swaybg --output VIRTUAL-1 --image "$WALLPAPER" --mode fill \
        >/var/log/aurum/swaybg.log 2>&1 &
else
    log "WARN: $WALLPAPER missing — using solid color fallback"
    swaybg --output VIRTUAL-1 --mode solid_color --color "#1c1c1e" \
        >/var/log/aurum/swaybg.log 2>&1 &
fi
sleep 1

# ── AurumOS desktop apps ─────────────────────────────────────────────────────
log "Arrancando desktop apps (Qt6 Wayland)..."
export QT_QPA_PLATFORM=wayland
export QT_WAYLAND_DISABLE_WINDOWDECORATION=1

# CRITICAL for headless/GPU-less preview: force Qt Quick to its software
# scene-graph backend so windows commit SHM (wl_shm) buffers instead of
# DMA-BUF / Wayland-EGL. wlroots' pixman renderer (which the headless backend
# uses without a real GPU) reads SHM and includes those buffers in
# wlr-screencopy frames. With EGL/DMA-BUF, the Qt windows render to the
# screen but are INVISIBLE to wlr-screencopy → wayvnc → noVNC, producing the
# infamous "black rectangles where apps should be" symptom. The penalty is
# CPU-only rendering, which for a static menubar+dock+finder is irrelevant.
# In a GPU-equipped install (production ISO), unset this so Qt6 uses EGL.
export QT_QUICK_BACKEND=software
export QSG_RHI_BACKEND=software

# Ensure PATH includes the dirs where our binaries + hyprctl live. Hyprland
# launches its children with an inherited environment; if PATH was empty in
# the container's entrypoint the dock's launch-dedup logic would fail to
# find hyprctl. Setting it explicitly here is defensive and harmless.
export PATH=/usr/local/bin:/usr/bin:/bin:${PATH}

aurum-menubar >/var/log/aurum/menubar.log 2>&1 &
sleep 1
aurum-dock    >/var/log/aurum/dock.log    2>&1 &
sleep 1
aurum-finder  >/var/log/aurum/finder.log  2>&1 &
sleep 3

# ── Position fix: drop the dock at bottom-center ─────────────────────────────
# Hyprland 0.55 honours `windowrule = match:class aurum-dock, move ...` on
# fresh windows, but in the headless preview the rule sometimes resolves
# BEFORE the QML Window.onCompleted ran (which is when width/height settle).
# The dispatcher path runs once the surface is fully sized, so it always lands
# correctly. Costs 1 ms and is idempotent.
DOCK_ADDR=$(hyprctl clients -j 2>/dev/null \
    | python3 -c 'import json,sys; d=json.load(sys.stdin); a=[w["address"] for w in d if w["class"]=="aurum-dock"]; print(a[0] if a else "")')
if [ -n "$DOCK_ADDR" ]; then
    # Pull the actual dock dimensions (depend on icon count) and centre at the
    # bottom with 12 px margin.
    read DW DH <<<"$(hyprctl clients -j 2>/dev/null \
        | python3 -c 'import json,sys; d=json.load(sys.stdin); w=[w for w in d if w["class"]=="aurum-dock"][0]; print(w["size"][0], w["size"][1])')"
    SCREEN_W=$(hyprctl monitors -j 2>/dev/null | python3 -c 'import json,sys; print(json.load(sys.stdin)[0]["width"])')
    SCREEN_H=$(hyprctl monitors -j 2>/dev/null | python3 -c 'import json,sys; print(json.load(sys.stdin)[0]["height"])')
    DX=$(( (SCREEN_W - DW) / 2 ))
    DY=$(( SCREEN_H - DH - 12 ))
    hyprctl dispatch focuswindow  "address:$DOCK_ADDR" >/dev/null 2>&1 || true
    hyprctl dispatch moveactive exact "$DX" "$DY"      >/dev/null 2>&1 || true
    log "Dock positioned at ($DX,$DY) size ${DW}x${DH}"
fi

# Sanity: at least one Aurum window registered in Hyprland?
if hyprctl clients 2>/dev/null | grep -qE 'aurum-(menubar|dock|finder)'; then
    log "Desktop apps OK ✓"
else
    log "WARN: no aurum windows in 'hyprctl clients' — checking logs..."
    for app in menubar dock finder; do
        log "── /var/log/aurum/${app}.log (tail) ──"
        tail -5 "/var/log/aurum/${app}.log" 2>&1 | sed 's|^|     |'
    done
fi

# ── Wait for first paintable frame on VIRTUAL-1 ──────────────────────────────
# wayvnc will refuse to start streaming if the output hasn't drawn a frame yet.
# Loop on hyprctl until at least one client is visible there.
for _ in $(seq 1 20); do
    if hyprctl monitors -j 2>/dev/null \
        | python3 -c "import sys,json; m=json.load(sys.stdin); \
                      print(any(x.get('name')=='VIRTUAL-1' and x.get('activeWorkspace',{}).get('id') for x in m))" 2>/dev/null \
        | grep -q True; then
        break
    fi
    sleep 0.5
done

# ── wayvnc ───────────────────────────────────────────────────────────────────
log "Arrancando wayvnc en :5900 (output: VIRTUAL-1)..."
wayvnc 0.0.0.0 5900 --output=VIRTUAL-1 >/var/log/aurum/wayvnc.log 2>&1 &
WAYVNC_PID=$!
sleep 3

# Fallback: try the first physical monitor if VIRTUAL-1 capture fails.
if grep -qiE 'protocol error|failed to|cannot' /var/log/aurum/wayvnc.log 2>/dev/null; then
    log "wayvnc error en VIRTUAL-1, intentando primer monitor disponible..."
    pkill wayvnc 2>/dev/null; sleep 1
    CAPTURE=$(hyprctl monitors -j 2>/dev/null \
        | python3 -c "import sys,json; m=json.load(sys.stdin); print(m[0]['name'])" 2>/dev/null \
        || echo "HDMI-A-1")
    log "  → capturing ${CAPTURE}"
    wayvnc 0.0.0.0 5900 --output="${CAPTURE}" >/var/log/aurum/wayvnc.log 2>&1 &
    sleep 2
fi

log "wayvnc OK ✓"
log ""
log "━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━"
log "  AurumOS preview → http://localhost:6080/vnc.html"
log "  VNC directo     → localhost:5900"
log "  Logs            → docker logs aurum-desktop"
log "━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━"

# ── noVNC HTML5 client (foreground; PID 1) ───────────────────────────────────
trap 'log "shutdown — killing children"; jobs -p | xargs -r kill 2>/dev/null; sleep 1; exit 0' INT TERM
exec websockify --web=/usr/share/novnc 6080 localhost:5900
