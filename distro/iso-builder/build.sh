#!/usr/bin/env bash
# ==============================================================================
# AurumOS ISO Builder Script
# Customizes Pop!_OS 24.04 LTS to create the AurumOS production-ready ISO.
# ==============================================================================

set -euo pipefail

# Configuration and Paths
BASE_DIR="$(cd "$(dirname "${BASH_SOURCE[0]}")/../.." && pwd)"
WORK_DIR="/tmp/aurum-iso-work"
ISO_DIR="${WORK_DIR}/iso"
CHROOT_DIR="${WORK_DIR}/chroot"
OUT_DIR="${BASE_DIR}/build"
DEFAULT_POP_ISO_URL="https://iso.pop-os.org/24.04/amd64/intel/1/pop-os_24.04_amd64_intel_1.iso" # Intel/AMD baseline

INPUT_ISO=""
VERSION="$(cat "${BASE_DIR}/VERSION" 2>/dev/null | tr -d '[:space:]')"
VERSION="${VERSION:-dev}"
OUTPUT_ISO="${OUT_DIR}/aurumos-v${VERSION}.iso"

# Output helpers
log_info()    { echo -e "\e[34m[INFO]\e[0m $*"; }
log_warn()    { echo -e "\e[33m[WARN]\e[0m $*"; }
log_error()   { echo -e "\e[31m[ERROR]\e[0m $*"; }
log_success() { echo -e "\e[32m[SUCCESS]\e[0m $*"; }

usage() {
    cat <<EOF
Usage: sudo $0 [options]

Options:
  -i, --input-iso <path>    Path to Pop!_OS 24.04 LTS base ISO. If omitted, downloads it automatically.
  -o, --output-iso <path>   Destination path for the built AurumOS ISO. Default: ${OUTPUT_ISO}
  -w, --work-dir <path>     Workspace directory for extraction. Default: ${WORK_DIR}
  -h, --help                Show this help message.
EOF
    exit 1
}

# Parse Arguments
while [[ $# -gt 0 ]]; do
    case "$1" in
        -i|--input-iso) INPUT_ISO="$2"; shift 2 ;;
        -o|--output-iso) OUTPUT_ISO="$2"; shift 2 ;;
        -w|--work-dir) WORK_DIR="$2"; shift 2 ;;
        -h|--help) usage ;;
        *) log_error "Unknown option: $1"; usage ;;
    esac
done

# Ensure running as root (required for mount, chroot, and filesystem editing)
if [[ $EUID -ne 0 ]]; then
   log_error "This script must be run as root (sudo)."
   exit 1
fi

# Set dynamic paths based on WORK_DIR
ISO_DIR="${WORK_DIR}/iso"
CHROOT_DIR="${WORK_DIR}/chroot"

# Step 1: Check System Dependencies
check_dependencies() {
    log_info "Verifying host system dependencies..."
    local deps=(xorriso mksquashfs unsquashfs rsync wget gpg curl)
    for dep in "${deps[@]}"; do
        if ! command -v "$dep" &>/dev/null; then
            log_error "Missing required tool: ${dep}. Install it using: apt install -y squashfs-tools xorriso rsync wget"
            exit 1
        fi
    done
    log_success "All dependencies present."
}

# Step 2: Acquire Base Pop!_OS ISO
get_base_iso() {
    if [[ -n "${INPUT_ISO}" ]]; then
        if [[ -f "${INPUT_ISO}" ]]; then
            log_info "Using local base ISO: ${INPUT_ISO}"
            return 0
        else
            log_error "Specified input ISO not found: ${INPUT_ISO}"
            exit 1
        fi
    fi

    INPUT_ISO="${WORK_DIR}/pop-os-base.iso"
    if [[ -f "${INPUT_ISO}" ]]; then
        log_info "Found existing base ISO in work directory: ${INPUT_ISO}"
        return 0
    fi

    log_info "No base ISO specified. Downloading Pop!_OS 24.04 ISO from ${DEFAULT_POP_ISO_URL}..."
    mkdir -p "${WORK_DIR}"
    wget -c "${DEFAULT_POP_ISO_URL}" -O "${INPUT_ISO}"
    log_success "Download complete."
}

# Step 3: Extract ISO and SquashFS
extract_iso() {
    log_info "Extracting base ISO files..."
    rm -rf "${ISO_DIR}" "${CHROOT_DIR}"
    mkdir -p "${ISO_DIR}" "${CHROOT_DIR}"

    # Mount ISO read-only to extract contents
    local mnt_point
    mnt_point=$(mktemp -d)
    mount -o loop,ro "${INPUT_ISO}" "${mnt_point}"
    
    log_info "Copying ISO contents..."
    rsync -a --exclude="/casper/filesystem.squashfs" "${mnt_point}/" "${ISO_DIR}/"
    
    log_info "Extracting SquashFS root filesystem..."
    unsquashfs -d "${CHROOT_DIR}" "${mnt_point}/casper/filesystem.squashfs"
    
    umount "${mnt_point}"
    rmdir "${mnt_point}"
    log_success "Extraction complete."
}

# Step 4: Bind Mount System Dirs for Chroot
mount_chroot() {
    log_info "Mounting system partitions into chroot environment..."
    mount --bind /dev "${CHROOT_DIR}/dev"
    mount --bind /dev/pts "${CHROOT_DIR}/dev/pts"
    mount --bind /proc "${CHROOT_DIR}/proc"
    mount --bind /sys "${CHROOT_DIR}/sys"
    mount --bind /run "${CHROOT_DIR}/run"
    # Copy resolv.conf to allow DNS inside chroot
    cp /etc/resolv.conf "${CHROOT_DIR}/etc/resolv.conf"
}

# Step 5: Clean Up Mounts
unmount_chroot() {
    log_info "Cleaning up mounts..."
    local mounts=("${CHROOT_DIR}/run" "${CHROOT_DIR}/sys" "${CHROOT_DIR}/proc" "${CHROOT_DIR}/dev/pts" "${CHROOT_DIR}/dev")
    for mnt in "${mounts[@]}"; do
        if mountpoint -q "$mnt"; then
            umount -f "$mnt" || log_warn "Failed to unmount $mnt"
        fi
    done
}

# Step 6: Customize Target System (Install packages, copy configurations)
customize_system() {
    log_info "Customizing AurumOS filesystem overlay..."

    # Ensure system config file lists exist
    local dl_list="${BASE_DIR}/distro/packages/dl.list"
    local sys_list="${BASE_DIR}/distro/packages/system.list"
    
    if [[ ! -f "${dl_list}" || ! -f "${sys_list}" ]]; then
        log_error "Package list files (dl.list / system.list) not found in ${BASE_DIR}/distro/packages/"
        exit 1
    fi

    # Copy package lists into chroot for processing
    mkdir -p "${CHROOT_DIR}/tmp/packages"
    cp "${dl_list}" "${CHROOT_DIR}/tmp/packages/dl.list"
    cp "${sys_list}" "${CHROOT_DIR}/tmp/packages/system.list"

    # Copy configurations overlay (seed) to user templates (/etc/skel) and global structures.
    # `wallpapers/` is excluded because it is not a dotfile — assets land in
    # /usr/share/backgrounds/aurumos/ via stage_wallpapers below.
    log_info "Applying seed configs..."
    if [[ -d "${BASE_DIR}/distro/seed" ]]; then
        mkdir -p "${CHROOT_DIR}/etc/skel/.config"
        rsync -av --exclude='wallpapers/' \
            "${BASE_DIR}/distro/seed/" "${CHROOT_DIR}/etc/skel/.config/"
    fi

    # AurumOS-authored terminal tweaks (lives outside seed/ because it isn't a
    # vendor dotfile — see apps/terminal-tweaks/README.md).
    if [[ -f "${BASE_DIR}/apps/terminal-tweaks/zellij.kdl" ]]; then
        install -d -m 0755 "${CHROOT_DIR}/etc/skel/.config/zellij"
        cp "${BASE_DIR}/apps/terminal-tweaks/zellij.kdl" \
           "${CHROOT_DIR}/etc/skel/.config/zellij/config.kdl"
    fi

    # Stage wallpaper assets system-wide.
    log_info "Staging wallpaper assets..."
    install -d -m 0755 "${CHROOT_DIR}/usr/share/backgrounds/aurumos"
    if [[ -d "${BASE_DIR}/distro/seed/wallpapers" ]]; then
        # Copy any real image files; the README.md placeholder is ignored.
        find "${BASE_DIR}/distro/seed/wallpapers" -maxdepth 2 -type f \
            \( -iname '*.jpg' -o -iname '*.jpeg' -o -iname '*.png' -o -iname '*.webp' \) \
            -exec cp {} "${CHROOT_DIR}/usr/share/backgrounds/aurumos/" \;
    fi

    # Stage the Hyprland builder, theme installer, and fork resources inside
    # the chroot so chroot_setup.sh can execute them against the target FS.
    log_info "Staging Phase 1 desktop installers..."
    install -d -m 0755 "${CHROOT_DIR}/tmp/aurum"
    cp "${BASE_DIR}/distro/iso-builder/build-hyprland.sh" "${CHROOT_DIR}/tmp/aurum/"
    cp -r "${BASE_DIR}/distro/hyprland-fork" "${CHROOT_DIR}/tmp/aurum/"
    cp "${BASE_DIR}/themes/install_themes.sh" "${CHROOT_DIR}/tmp/aurum/"

    # Stage Phase 4 post-install scripts + pip-requirements + tests.
    log_info "Staging Phase 4 DL stack installers + tests..."
    cp "${BASE_DIR}/distro/post-install/02-install-dl-stack.sh"     "${CHROOT_DIR}/tmp/aurum/"
    cp "${BASE_DIR}/distro/post-install/03-install-llm-runtimes.sh" "${CHROOT_DIR}/tmp/aurum/"
    cp "${BASE_DIR}/distro/packages/pip-requirements.txt"           "${CHROOT_DIR}/tmp/aurum/pip-requirements.txt"
    install -d -m 0755 "${CHROOT_DIR}/tmp/aurum/tests"
    cp "${BASE_DIR}/tests/dl_smoke.py"        "${CHROOT_DIR}/tmp/aurum/tests/dl_smoke.py"
    cp "${BASE_DIR}/tests/dl_bench.py"        "${CHROOT_DIR}/tmp/aurum/tests/dl_bench.py"
    cp "${BASE_DIR}/tests/aurum-dl-verify"    "${CHROOT_DIR}/tmp/aurum/tests/aurum-dl-verify"

    # Stage Phase 6 perf-tune script + boot/idle/acceptance bench tools.
    cp "${BASE_DIR}/distro/post-install/04-perf-tune.sh"            "${CHROOT_DIR}/tmp/aurum/"
    cp "${BASE_DIR}/tests/boot_bench.sh"      "${CHROOT_DIR}/tmp/aurum/tests/boot_bench.sh"
    cp "${BASE_DIR}/tests/idle_bench.sh"      "${CHROOT_DIR}/tmp/aurum/tests/idle_bench.sh"
    cp "${BASE_DIR}/tests/acceptance.sh"      "${CHROOT_DIR}/tmp/aurum/tests/acceptance.sh"

    # Stage system-wide .desktop entries for the menu / dock / spotlight.
    log_info "Staging system-wide application entries..."
    install -d -m 0755 "${CHROOT_DIR}/usr/share/applications"
    cp "${BASE_DIR}"/distro/applications/*.desktop \
       "${CHROOT_DIR}/usr/share/applications/"

    # Stage Phase 2 source trees so chroot_setup.sh can build them in-place.
    # We build inside the chroot rather than cross-copying binaries so the
    # ELF interpreter and shared library paths match the target system.
    log_info "Staging Phase 2 source trees (libs/desktop/daemons)..."
    rsync -a --delete \
        --exclude='build/' --exclude='target/' \
        "${BASE_DIR}/libs/"     "${CHROOT_DIR}/tmp/aurum/libs/"
    rsync -a --delete \
        --exclude='build/' --exclude='target/' \
        "${BASE_DIR}/desktop/"  "${CHROOT_DIR}/tmp/aurum/desktop/"
    rsync -a --delete \
        --exclude='build/' --exclude='target/' \
        "${BASE_DIR}/daemons/"  "${CHROOT_DIR}/tmp/aurum/daemons/"
    cp "${BASE_DIR}/CMakeLists.txt" "${CHROOT_DIR}/tmp/aurum/CMakeLists.txt"

    # Install systemd units shipped alongside daemons. user-level units live in
    # /usr/lib/systemd/user so they apply to every user without per-account setup.
    install -d -m 0755 "${CHROOT_DIR}/usr/lib/systemd/user"
    cp "${BASE_DIR}/daemons/gpu-monitor/systemd/aurum-gpu-monitor.service" \
       "${CHROOT_DIR}/usr/lib/systemd/user/aurum-gpu-monitor.service"
    cp "${BASE_DIR}/daemons/spotlight-indexer/systemd/aurum-spotlight-indexer.service" \
       "${CHROOT_DIR}/usr/lib/systemd/user/aurum-spotlight-indexer.service"
    cp "${BASE_DIR}/daemons/ml-jobs-tracker/systemd/aurum-ml-jobs-tracker.service" \
       "${CHROOT_DIR}/usr/lib/systemd/user/aurum-ml-jobs-tracker.service"

    # Phase 3: ship the parquet preview helper system-wide so the Quick Look
    # path is the same on every machine regardless of which venv is active.
    install -d -m 0755 "${CHROOT_DIR}/usr/local/share/aurum-os/scripts"
    install -m 0755 "${BASE_DIR}/scripts/parquet_peek.py" \
        "${CHROOT_DIR}/usr/local/share/aurum-os/scripts/parquet_peek.py"

    # Inject Kernel Tuning rules
    log_info "Applying kernel performance profiles..."
    mkdir -p "${CHROOT_DIR}/etc/sysctl.d"
    cat <<EOF > "${CHROOT_DIR}/etc/sysctl.d/99-aurumos.conf"
# AurumOS Core Tuning Parameters
vm.swappiness = 0
vm.dirty_ratio = 10
vm.dirty_background_ratio = 5
vm.vfs_cache_pressure = 50
vm.nr_hugepages = 0
vm.max_map_count = 1600000
kernel.numa_balancing = 1
net.core.wmem_max = 16777216
net.core.rmem_max = 16777216
EOF

    # Configure custom services (like disabling standard swap and setting up ZRAM via systemd)
    log_info "Configuring memory manager rules (ZRAM + Transparent HugePages)..."
    cat <<EOF > "${CHROOT_DIR}/etc/systemd/system/aurum-zram.service"
[Unit]
Description=AurumOS ZRAM Setup
After=multi-user.target

[Service]
Type=oneshot
RemainAfterExit=yes
ExecStart=/sbin/modprobe zram
ExecStart=/bin/bash -c "echo zstd > /sys/block/zram0/comp_algorithm"
ExecStart=/bin/bash -c "echo 32G > /sys/block/zram0/disksize"
ExecStart=/sbin/mkswap /dev/zram0
ExecStart=/sbin/swapon -p 100 /dev/zram0

[Install]
WantedBy=multi-user.target
EOF

    # Enable ZRAM service in chroot
    ln -sf "/etc/systemd/system/aurum-zram.service" "${CHROOT_DIR}/etc/systemd/system/multi-user.target.wants/aurum-zram.service"

    # Write chroot install execution script
    log_info "Writing chroot command execution script..."
    cat <<'EOF' > "${CHROOT_DIR}/tmp/chroot_setup.sh"
#!/usr/bin/env bash
set -ex

# Update package sources
apt-get update

# Read package lists, filter comments/empty lines, and install
system_packages=$(grep -v '^#' /tmp/packages/system.list | grep -v '^$')
apt-get install -y --no-install-recommends $system_packages

# Install Deep Learning runtimes and drivers (excluding py packages)
dl_system_packages=$(grep -v '^#' /tmp/packages/dl.list | grep -v '^$' | grep -v '==' | grep -v '\[')
apt-get install -y --no-install-recommends $dl_system_packages

# --- Phase 4: Python DL stack (PyTorch / JAX / TF / vLLM via uv) --------------
# Driven by pip-requirements.txt — the single source of truth for the DL surface.
# The installer creates /opt/aurum-dl-venv, symlinks jupyter-lab/marimo to
# /usr/local/bin, and writes /etc/profile.d/aurum-dl.sh.
PIP_REQS=/tmp/aurum/pip-requirements.txt \
    bash /tmp/aurum/02-install-dl-stack.sh

# Install Claude Code / Aider globally as uv tool managed utilities. These are
# AI dev tools, not core DL, so they live under uv's tool namespace.
export PATH="/root/.local/bin:${PATH}"
uv tool install claude-code || true
uv tool install aider-chat  || true

# --- Phase 4: local LLM runtimes (Ollama + LM Studio CLI bootstrap) ----------
bash /tmp/aurum/03-install-llm-runtimes.sh

# Ship the DL verification harness system-wide.
install -d -m 0755 /usr/local/share/aurum-os/tests
install -m 0644 /tmp/aurum/tests/dl_smoke.py     /usr/local/share/aurum-os/tests/dl_smoke.py
install -m 0644 /tmp/aurum/tests/dl_bench.py     /usr/local/share/aurum-os/tests/dl_bench.py
install -m 0755 /tmp/aurum/tests/aurum-dl-verify /usr/local/bin/aurum-dl-verify
# Phase 6: acceptance/boot/idle scripts ship alongside the DL tests so the
# beta user can rerun the budget checks any time.
install -m 0755 /tmp/aurum/tests/boot_bench.sh   /usr/local/share/aurum-os/tests/boot_bench.sh
install -m 0755 /tmp/aurum/tests/idle_bench.sh   /usr/local/share/aurum-os/tests/idle_bench.sh
install -m 0755 /tmp/aurum/tests/acceptance.sh   /usr/local/bin/aurum-acceptance

# --- Phase 6: installer backend (distinst) -----------------------------------
# The Pop!_OS distinst binary is already in their repo; pull it explicitly so
# the live ISO can launch aurum-installer without the user installing more.
apt-get install -y --no-install-recommends distinst 2>/dev/null \
    || echo "[build] WARN: distinst package not found in apt; installer will fall back to manual mode" >&2

# --- Phase 6: boot + idle performance tuning ---------------------------------
bash /tmp/aurum/04-perf-tune.sh

# --- Phase 1: macOS-like desktop stack -----------------------------------------
# Build the AurumOS Hyprland fork (installs to /usr/local + stages aurum.conf
# under /etc/aurum/hypr/). Run before the theme installer so the compositor
# binary exists in PATH when the theme step probes for it.
bash /tmp/aurum/build-hyprland.sh

# Install WhiteSur GTK theme, icons, cursors and global theme defaults.
bash /tmp/aurum/install_themes.sh

# --- Phase 2: AurumOS desktop binaries -----------------------------------------
# Need Rust for the gpu-monitor daemon. Use rustup pinned to a stable channel.
export RUSTUP_HOME=/usr/local/rustup
export CARGO_HOME=/usr/local/cargo
curl --proto '=https' --tlsv1.2 -sSf https://sh.rustup.rs \
    | sh -s -- -y --no-modify-path --default-toolchain stable
export PATH="${CARGO_HOME}/bin:${PATH}"

# Build the Qt/C++ DE components (libs + desktop) via the top-level CMake.
# BUILD_TESTS=OFF inside the chroot: the test suite needs a live GPU/Wayland.
apt-get install -y --no-install-recommends \
    qt6-base-dev qt6-declarative-dev qt6-wayland \
    libqt6svg6 libgl1-mesa-dev pkg-config

cmake -S /tmp/aurum -B /tmp/aurum/build \
    -DCMAKE_BUILD_TYPE=Release \
    -DCMAKE_INSTALL_PREFIX=/usr/local \
    -DBUILD_TESTS=OFF
cmake --build /tmp/aurum/build -j"$(nproc)"
cmake --install /tmp/aurum/build

# Build the Rust daemons. Release profiles in each Cargo.toml apply thin LTO,
# codegen-units=1, strip=true so the final ISO doesn't carry debug symbols.
cargo build --release --manifest-path /tmp/aurum/daemons/gpu-monitor/Cargo.toml
cargo build --release --manifest-path /tmp/aurum/daemons/spotlight-indexer/Cargo.toml
cargo build --release --manifest-path /tmp/aurum/daemons/ml-jobs-tracker/Cargo.toml
install -m 0755 /tmp/aurum/daemons/gpu-monitor/target/release/aurum-gpu-monitor \
    /usr/local/bin/aurum-gpu-monitor
install -m 0755 /tmp/aurum/daemons/spotlight-indexer/target/release/aurum-spotlight-indexer \
    /usr/local/bin/aurum-spotlight-indexer
install -m 0755 /tmp/aurum/daemons/ml-jobs-tracker/target/release/aurum-ml-jobs-tracker \
    /usr/local/bin/aurum-ml-jobs-tracker

# Enable user services so they auto-start with graphical-session.target.
install -d -m 0755 /usr/lib/systemd/user/graphical-session.target.wants
ln -sf /usr/lib/systemd/user/aurum-gpu-monitor.service \
       /usr/lib/systemd/user/graphical-session.target.wants/aurum-gpu-monitor.service
ln -sf /usr/lib/systemd/user/aurum-spotlight-indexer.service \
       /usr/lib/systemd/user/graphical-session.target.wants/aurum-spotlight-indexer.service
ln -sf /usr/lib/systemd/user/aurum-ml-jobs-tracker.service \
       /usr/lib/systemd/user/graphical-session.target.wants/aurum-ml-jobs-tracker.service

# Rust toolchain isn't shipped in the final image — remove the installer.
rm -rf "${RUSTUP_HOME}" "${CARGO_HOME}"
unset RUSTUP_HOME CARGO_HOME

# Set performance governor to CPU
echo "performance" | tee /sys/devices/system/cpu/cpu*/cpufreq/scaling_governor || true

# Clean up apt caches and staging
apt-get clean
rm -rf /var/lib/apt/lists/* /tmp/aurum
EOF

    # Run setup script inside chroot
    chmod +x "${CHROOT_DIR}/tmp/chroot_setup.sh"
    chroot "${CHROOT_DIR}" /tmp/chroot_setup.sh
    
    # Cleanup setup files inside chroot
    rm -rf "${CHROOT_DIR}/tmp/chroot_setup.sh" "${CHROOT_DIR}/tmp/packages"
    log_success "Chroot customizations completed."
}

# Step 7: Repackage SquashFS
rebuild_squashfs() {
    log_info "Recompressing SquashFS (using zstd for fast compression and load speed)..."
    rm -f "${ISO_DIR}/casper/filesystem.squashfs"
    mksquashfs "${CHROOT_DIR}" "${ISO_DIR}/casper/filesystem.squashfs" -comp zstd -b 1048576 -noappend
    log_success "SquashFS rebuilt."
}

# Step 8: Build Custom ISO image
generate_iso() {
    log_info "Regenerating checksum files..."
    (cd "${ISO_DIR}" && find . -type f -not -name 'md5sum.txt' -not -path './isolinux/*' -exec md5sum {} + > md5sum.txt)

    log_info "Generating hybrid ISO image via xorriso..."
    mkdir -p "$(dirname "${OUTPUT_ISO}")"

    # Execute xorriso commands mirroring Pop!_OS parameters
    xorriso -as mkisofs \
        -r -V "AurumOS_Live" \
        -o "${OUTPUT_ISO}" \
        -J -joliet-long \
        -b isolinux/isolinux.bin \
        -c isolinux/boot.cat \
        -no-emul-boot -boot-load-size 4 -boot-info-table \
        -eltorito-alt-boot \
        -e boot/grub/efi.img \
        -no-emul-boot \
        -isohybrid-gpt-basdat \
        "${ISO_DIR}"

    log_success "Custom ISO built successfully: ${OUTPUT_ISO}"
}

# Master Flow execution
main() {
    check_dependencies
    get_base_iso
    extract_iso

    trap unmount_chroot EXIT INT TERM

    mount_chroot
    customize_system
    unmount_chroot

    rebuild_squashfs
    generate_iso
}

main
