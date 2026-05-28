#!/usr/bin/env bash
# ==============================================================================
# AurumOS — boot + idle performance tuning.
#
# Budget (see docs/adr/0006-performance-budget.md):
#   * Boot to graphical session: <3 s on NVMe.
#   * Idle RAM with dock + menubar + compositor: <600 MB.
#
# This script applies the static changes — service masking, kernel cmdline,
# initramfs/bootloader tweaks. Runtime benchmarking lives in
# tests/boot_bench.sh, which the user runs post-install.
#
# Idempotent: every operation either creates a marker file or short-circuits
# when its end state is already in effect.
# ==============================================================================

set -euo pipefail

log()  { echo -e "\e[34m[perf]\e[0m $*"; }
warn() { echo -e "\e[33m[perf]\e[0m $*" >&2; }

[[ $EUID -eq 0 ]] || { echo "must be run as root" >&2; exit 1; }

# AMD-LITE PATCH: load profile so we can be polite to laptop users.
PROFILE_CONF="${AURUM_PROFILE_CONF:-/etc/aurum/profile.conf}"
if [[ -r "${PROFILE_CONF}" ]]; then
    set -a
    # shellcheck source=/dev/null
    source "${PROFILE_CONF}"
    set +a
fi
AURUM_PROFILE="${AURUM_PROFILE:-lite}"


# --- 1. Mask non-essential services -------------------------------------------
# These add 200-800 ms each to the critical boot chain and a DL workstation
# doesn't use them by default. Users can `systemctl unmask <x>` later.
SERVICES_TO_MASK=(
    bluetooth.service
    cups.service
    cups-browsed.service
    ModemManager.service
    avahi-daemon.service
    avahi-daemon.socket
    snapd.service
    snapd.socket
    snapd.seeded.service
    networkd-dispatcher.service
    apport.service
    motd-news.timer
)

# AMD-LITE PATCH: on lite profile, do NOT mask bluetooth/cups/printer.
if [[ "${AURUM_PROFILE}" == "lite" ]]; then
    log "lite profile: skipping bluetooth/cups/printer masking"
    LITE_SAFE_SERVICES=( snapd.service snapd.socket snapd.seeded.service apport.service motd-news.timer )
    for svc in "${LITE_SAFE_SERVICES[@]}"; do
        systemctl mask "${svc}" 2>/dev/null || true
    done
else
    log "masking non-essential services (profile=${AURUM_PROFILE})..."
    for svc in "${SERVICES_TO_MASK[@]}"; do
        systemctl mask "${svc}" 2>/dev/null || true
    done
fi

# Disable timers that wake the system periodically.
systemctl disable apt-daily.timer        apt-daily.service        2>/dev/null || true
systemctl disable apt-daily-upgrade.timer apt-daily-upgrade.service 2>/dev/null || true
systemctl disable fstrim.timer 2>/dev/null || true   # bcachefs runs its own GC

# --- 2. Kernel command line ---------------------------------------------------
# `quiet`              — kill verbose kernel messages on screen
# `splash`             — Pop!_OS's plymouth handles this; we still keep it
# `nowatchdog`         — skips the per-core hardware watchdog probe (~80 ms)
# `mitigations=auto`   — explicit so Pop's default isn't surprising later
# `nvidia-drm.modeset=1` — required for Wayland sessions with NVIDIA
CMDLINE_FILE=/etc/default/grub
if [[ -f "${CMDLINE_FILE}" ]] && ! grep -q 'AurumOS perf cmdline' "${CMDLINE_FILE}"; then
    log "applying GRUB_CMDLINE_LINUX_DEFAULT..."
    {
        echo ""
        echo "# AurumOS perf cmdline"
        echo "GRUB_CMDLINE_LINUX_DEFAULT=\"quiet splash nowatchdog mitigations=auto nvidia-drm.modeset=1\""
        echo "GRUB_TIMEOUT=0"
        echo "GRUB_TIMEOUT_STYLE=hidden"
    } >> "${CMDLINE_FILE}"
    update-grub 2>/dev/null || true
fi

# Pop!_OS uses systemd-boot on UEFI installs by default. Tune that too if present.
if command -v kernelstub >/dev/null 2>&1; then
    log "applying kernelstub options for systemd-boot..."
    kernelstub --add-options "nowatchdog nvidia-drm.modeset=1" 2>/dev/null || true
fi

# --- 2b. inotify / kernel limits -----------------------------------------------
# Default `fs.inotify.max_user_watches` is 524288. The aurum-spotlight-indexer
# watches every dir under ~/datasets, ~/models, ~/notebooks recursively, plus
# the editor LSPs (rust-analyzer, jedi-language-server) tend to watch their
# own trees. A DL workstation easily exceeds 500k files. Bump to 2M.
install -d /etc/sysctl.d
cat > /etc/sysctl.d/98-aurumos-inotify.conf <<'CFG'
# AurumOS: lift inotify watch limit so the Spotlight indexer + LSP daemons can
# share the budget without "no space left on device" errors on watch_add.
fs.inotify.max_user_watches   = 2097152
fs.inotify.max_user_instances = 8192
fs.inotify.max_queued_events  = 65536
CFG

# --- 3. systemd start timeouts ------------------------------------------------
# Default DefaultTimeoutStartSec is 90 s. On a healthy system every unit
# starts in <2 s; if one stalls, faster failure is better than a hung boot.
install -d /etc/systemd/system.conf.d
cat > /etc/systemd/system.conf.d/aurumos-timeouts.conf <<'CFG'
[Manager]
DefaultTimeoutStartSec=15s
DefaultTimeoutStopSec=10s
DefaultRestartSec=1s
CFG

# --- 4. Trim the udev rule scan time ------------------------------------------
# Pop!_OS ships hwdb files for almost every laptop ever made. They don't all
# apply to a DL workstation, but rebuilding hwdb is risky — leave it alone.
# Instead, ensure systemd-modules-load doesn't probe USB serial drivers we
# never need on a workstation.
cat > /etc/modprobe.d/aurumos-blacklist.conf <<'CFG'
# Modules unused on a DL workstation; skipping them shaves udev settle time.
blacklist pcspkr
blacklist snd_pcsp
blacklist iTCO_wdt
blacklist sp5100_tco
CFG

# --- 5. zram swap (already configured by build.sh aurum-zram.service) --------
# Nothing to do here — keep this hook so a future ADR can extend zram tuning.

log "boot/idle tuning applied"
log "verify with: systemd-analyze blame    +    ps_mem (see tests/idle_bench.sh)"
