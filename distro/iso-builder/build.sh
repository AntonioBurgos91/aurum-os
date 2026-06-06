#!/usr/bin/env bash
# ==============================================================================
# AurumOS ISO Builder Script
#
# Builds a bootable AurumOS live ISO from one of two bases:
#   --base ubuntu  (default)  Self-contained: debootstraps Ubuntu 24.04 from the
#                             official archive. No external ISO download, so it
#                             never breaks when a vendor moves their ISO around.
#   --base popos              Customizes a Pop!_OS 24.04 base ISO (closest to the
#                             original design). Requires AURUM_POPOS_ISO_URL or a
#                             local --input-iso, because Pop!_OS rotates its ISO
#                             URLs and we refuse to hard-code one that 404s.
# ==============================================================================

set -euo pipefail

# Configuration and Paths
BASE_DIR="$(cd "$(dirname "${BASH_SOURCE[0]}")/../.." && pwd)"
WORK_DIR="/tmp/aurum-iso-work"
ISO_DIR="${WORK_DIR}/iso"
CHROOT_DIR="${WORK_DIR}/chroot"
OUT_DIR="${BASE_DIR}/build"
# Pop!_OS rotates its ISO URLs (the old hard-coded 24.04/intel/1 path now 404s),
# so we DON'T hard-code one. Pass a working URL via AURUM_POPOS_ISO_URL or hand a
# local ISO with --input-iso when using --base popos.
DEFAULT_POP_ISO_URL="${AURUM_POPOS_ISO_URL:-}"

# Base selection: "ubuntu" (debootstrap, self-contained) or "popos" (vendor ISO).
BASE_FLAVOR="ubuntu"
# Ubuntu suite + mirror used by the debootstrap path.
UBUNTU_SUITE="${AURUM_UBUNTU_SUITE:-noble}"
UBUNTU_MIRROR="${AURUM_UBUNTU_MIRROR:-http://archive.ubuntu.com/ubuntu/}"

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
  -b, --base <ubuntu|popos> Base system to build from. Default: ubuntu
                            ubuntu = debootstrap from the Ubuntu archive (self-contained).
                            popos  = customize a Pop!_OS base ISO (needs --input-iso or
                                     AURUM_POPOS_ISO_URL).
  -i, --input-iso <path>    (popos only) Path to a local Pop!_OS 24.04 base ISO.
  -o, --output-iso <path>   Destination path for the built AurumOS ISO. Default: ${OUTPUT_ISO}
  -w, --work-dir <path>     Workspace directory. Default: ${WORK_DIR}
  -h, --help                Show this help message.

Environment:
  AURUM_POPOS_ISO_URL   URL to fetch the Pop!_OS base ISO from (popos mode).
  AURUM_UBUNTU_SUITE    Ubuntu suite for debootstrap (default: noble).
  AURUM_UBUNTU_MIRROR   Ubuntu mirror for debootstrap.
EOF
    exit 1
}

# Parse Arguments
while [[ $# -gt 0 ]]; do
    case "$1" in
        -b|--base) BASE_FLAVOR="$2"; shift 2 ;;
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
    log_info "Verifying host system dependencies (base=${BASE_FLAVOR})..."
    local deps=(xorriso mksquashfs unsquashfs rsync wget gpg curl)
    if [[ "${BASE_FLAVOR}" == "ubuntu" ]]; then
        # debootstrap + grub-mkrescue replace the ISO-extraction path.
        deps+=(debootstrap grub-mkrescue)
    fi
    local missing=()
    for dep in "${deps[@]}"; do
        command -v "$dep" &>/dev/null || missing+=("$dep")
    done
    if (( ${#missing[@]} )); then
        log_error "Missing required tools: ${missing[*]}"
        log_error "Install with: apt install -y squashfs-tools xorriso rsync wget debootstrap grub-pc-bin grub-efi-amd64-bin"
        exit 1
    fi
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

    if [[ -z "${DEFAULT_POP_ISO_URL}" ]]; then
        log_error "No Pop!_OS base ISO available."
        log_error "Pop!_OS rotates its download URLs, so this script does not hard-code one."
        log_error "Either: (a) pass a local ISO with --input-iso <path>, or"
        log_error "        (b) set AURUM_POPOS_ISO_URL to a current Pop!_OS 24.04 ISO URL, or"
        log_error "        (c) use the self-contained Ubuntu base: --base ubuntu"
        exit 1
    fi
    log_info "Downloading Pop!_OS 24.04 ISO from ${DEFAULT_POP_ISO_URL}..."
    mkdir -p "${WORK_DIR}"
    wget -c "${DEFAULT_POP_ISO_URL}" -O "${INPUT_ISO}"
    log_success "Download complete."
}

# Step 2b: Build a minimal Ubuntu rootfs via debootstrap (self-contained path).
# Produces the same CHROOT_DIR + ISO_DIR/casper layout the rest of the script
# expects, so customize_system / rebuild_squashfs work unchanged.
bootstrap_ubuntu() {
    log_info "Building Ubuntu ${UBUNTU_SUITE} base via debootstrap (self-contained)..."
    rm -rf "${ISO_DIR}" "${CHROOT_DIR}"
    mkdir -p "${ISO_DIR}/casper" "${ISO_DIR}/boot/grub" "${CHROOT_DIR}"

    debootstrap --variant=minbase --arch=amd64 \
        --components=main,universe \
        --include=systemd,systemd-sysv \
        "${UBUNTU_SUITE}" "${CHROOT_DIR}" "${UBUNTU_MIRROR}"

    # apt sources inside the target so the chroot stage can install packages.
    cat > "${CHROOT_DIR}/etc/apt/sources.list" <<APT
deb ${UBUNTU_MIRROR} ${UBUNTU_SUITE} main universe multiverse restricted
deb ${UBUNTU_MIRROR} ${UBUNTU_SUITE}-updates main universe multiverse restricted
deb ${UBUNTU_MIRROR} ${UBUNTU_SUITE}-security main universe multiverse restricted
APT

    # Kernel + live-boot tooling so the squashfs can boot as a live system.
    mount_chroot
    chroot "${CHROOT_DIR}" /bin/bash -c '
        export DEBIAN_FRONTEND=noninteractive
        apt-get update -qq
        apt-get install -y --no-install-recommends             linux-image-generic casper             grub-pc-bin grub-efi-amd64-bin grub-common
    '
    unmount_chroot

    log_success "Ubuntu base ready."
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

    # Stage Wave 8/9 — hardware-profile detector + SOTA-2026 installers (00, 05–12).
    # 00 is the profile detector — must run BEFORE 05–12 so they read /etc/aurum/profile.conf.
    # 05  quantization (bitsandbytes, AutoGPTQ, AutoAWQ)
    # 06  fine-tuning (Unsloth, TorchTune, Axolotl, DeepSpeed — profile-gated)
    # 07  LLM serving (vLLM, SGLang, TGI, LiteLLM — gated)
    # 08  LLM workflows (DSPy, Instructor, Outlines, Pydantic AI, MCP) — all profiles
    # 09  AI-augmented coding (Continue.dev, Aider, Claude Code CLI)
    # 10  LLM observability (Langfuse self-hosted, Phoenix, TruLens, Ragas, DeepEval)
    # 11  CV + multimodal (YOLOv11, SAM2, DINOv2, ComfyUI — gated)
    # 12  Model Pack Manager (aurum-model-pack CLI + 6 manifests)
    log_info "Staging Wave 8/9 SOTA-2026 installers + Hyprland drop-ins + model packs..."
    for f in 00-detect-profile.sh \
             05-install-quantization.sh 06-install-finetuning.sh \
             07-install-llm-serving.sh 08-install-llm-workflows.sh \
             09-install-ai-coding.sh 10-install-observability.sh \
             11-install-cv-multimodal.sh 12-install-model-pack-manager.sh \
             13-install-flatpak.sh; do
        cp "${BASE_DIR}/distro/post-install/${f}" "${CHROOT_DIR}/tmp/aurum/"
    done
    # Pinned pip requirements per domain
    for f in pip-requirements-quant.txt pip-requirements-finetune.txt \
             pip-requirements-serving.txt pip-requirements-workflows.txt \
             pip-requirements-coding.txt pip-requirements-observability.txt \
             pip-requirements-cv.txt; do
        cp "${BASE_DIR}/distro/packages/${f}" "${CHROOT_DIR}/tmp/aurum/"
    done
    # Profile-detect systemd unit (regenerates /etc/aurum/profile.conf on boot)
    install -d -m 0755 "${CHROOT_DIR}/etc/systemd/system"
    cp "${BASE_DIR}/daemons/profile-detect/systemd/aurum-detect-profile.service" \
       "${CHROOT_DIR}/etc/systemd/system/aurum-detect-profile.service"
    # Hyprland drop-in window rules (one file per Wave 8 agent, no aurum.conf collisions)
    install -d -m 0755 "${CHROOT_DIR}/etc/aurum/hypr/conf.d"
    cp "${BASE_DIR}"/distro/hyprland-fork/conf.d/*.conf \
       "${CHROOT_DIR}/etc/aurum/hypr/conf.d/" 2>/dev/null || true
    # Model Pack manifests + assets (LiteLLM proxy config, Langfuse compose, Continue.dev template)
    install -d -m 0755 "${CHROOT_DIR}/etc/aurum/model-packs"
    cp "${BASE_DIR}"/distro/assets/model-packs/*.yaml \
       "${CHROOT_DIR}/etc/aurum/model-packs/" 2>/dev/null || true
    # Installed-version marker the updater (aurum-update) compares against the
    # latest GitHub release. Written from the build's VERSION so the running
    # system always knows what it is.
    install -d -m 0755 "${CHROOT_DIR}/etc/aurum"
    echo "${VERSION}" > "${CHROOT_DIR}/etc/aurum/version"
    install -d -m 0755 "${CHROOT_DIR}/tmp/aurum/assets"
    cp "${BASE_DIR}/distro/assets/litellm-config.yaml"        "${CHROOT_DIR}/tmp/aurum/assets/" 2>/dev/null || true
    cp "${BASE_DIR}/distro/assets/langfuse-docker-compose.yml" "${CHROOT_DIR}/tmp/aurum/assets/" 2>/dev/null || true
    cp "${BASE_DIR}/distro/assets/langfuse-env.template"       "${CHROOT_DIR}/tmp/aurum/assets/" 2>/dev/null || true
    cp "${BASE_DIR}/distro/assets/continue-config.json"        "${CHROOT_DIR}/tmp/aurum/assets/" 2>/dev/null || true
    # Recipes + tools (aurum-finetune, aurum-launch-*, aurum-model-pack, aurum-mcp-template)
    install -d -m 0755 "${CHROOT_DIR}/tmp/aurum/recipes"
    rsync -a "${BASE_DIR}/recipes/" "${CHROOT_DIR}/tmp/aurum/recipes/"
    install -d -m 0755 "${CHROOT_DIR}/tmp/aurum/tools"
    cp "${BASE_DIR}/tools/aurum-finetune"            "${CHROOT_DIR}/tmp/aurum/tools/" 2>/dev/null || true
    cp "${BASE_DIR}/tools/aurum-launch-vllm"         "${CHROOT_DIR}/tmp/aurum/tools/" 2>/dev/null || true
    cp "${BASE_DIR}/tools/aurum-launch-sglang"       "${CHROOT_DIR}/tmp/aurum/tools/" 2>/dev/null || true
    cp "${BASE_DIR}/tools/aurum-launch-tgi"          "${CHROOT_DIR}/tmp/aurum/tools/" 2>/dev/null || true
    cp "${BASE_DIR}/tools/aurum-launch-litellm"      "${CHROOT_DIR}/tmp/aurum/tools/" 2>/dev/null || true
    cp "${BASE_DIR}/tools/aurum-launch-langfuse"     "${CHROOT_DIR}/tmp/aurum/tools/" 2>/dev/null || true
    cp "${BASE_DIR}/tools/aurum-launch-phoenix"      "${CHROOT_DIR}/tmp/aurum/tools/" 2>/dev/null || true
    cp "${BASE_DIR}/tools/aurum-launch-comfyui"      "${CHROOT_DIR}/tmp/aurum/tools/" 2>/dev/null || true
    cp "${BASE_DIR}/tools/aurum-eval"                "${CHROOT_DIR}/tmp/aurum/tools/" 2>/dev/null || true
    cp "${BASE_DIR}/tools/aurum-mcp-template"        "${CHROOT_DIR}/tmp/aurum/tools/" 2>/dev/null || true
    cp "${BASE_DIR}/tools/aurum-configure-continue.sh" "${CHROOT_DIR}/tmp/aurum/tools/" 2>/dev/null || true
    cp "${BASE_DIR}/tools/aurum-cv-download-models"  "${CHROOT_DIR}/tmp/aurum/tools/" 2>/dev/null || true
    cp "${BASE_DIR}/tools/aurum-model-pack"          "${CHROOT_DIR}/tmp/aurum/tools/" 2>/dev/null || true
    cp "${BASE_DIR}/tools/aurum-model-pack-helpers.py" "${CHROOT_DIR}/tmp/aurum/tools/" 2>/dev/null || true
    cp "${BASE_DIR}/tools/aurum-update"              "${CHROOT_DIR}/tmp/aurum/tools/" 2>/dev/null || true
    cp "${BASE_DIR}/tools/aurum-update-apply"        "${CHROOT_DIR}/tmp/aurum/tools/" 2>/dev/null || true
    install -d -m 0755 "${CHROOT_DIR}/tmp/aurum/polkit"
    cp "${BASE_DIR}/distro/polkit/org.aurumos.update.policy" "${CHROOT_DIR}/tmp/aurum/polkit/" 2>/dev/null || true
    # CV training pipeline (point-cloud segmentation) — Python, installed
    # system-wide so the "CV Training Studio" launcher can run it.
    install -d -m 0755 "${CHROOT_DIR}/tmp/aurum/cv-training"
    cp "${BASE_DIR}"/apps/pointcloud-viewer/training/*.py \
       "${CHROOT_DIR}/tmp/aurum/cv-training/" 2>/dev/null || true
    cp "${BASE_DIR}/apps/pointcloud-viewer/training/aurum-cv-train" \
       "${CHROOT_DIR}/tmp/aurum/cv-training/" 2>/dev/null || true
    # App icons (256x256) for the menu/dock. Staged here and installed into the
    # hicolor theme by chroot_setup so QIcon::fromTheme(<id>) resolves them.
    install -d -m 0755 "${CHROOT_DIR}/tmp/aurum/app-icons"
    cp "${BASE_DIR}"/distro/assets/icons/*.png \
       "${CHROOT_DIR}/tmp/aurum/app-icons/" 2>/dev/null || true

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
    # Native apps (the point-cloud viewer is a C++/Qt target built by the
    # top-level CMake; its Python trainer is staged separately below).
    rsync -a --delete \
        --exclude='build/' --exclude='target/' --exclude='__pycache__/' \
        "${BASE_DIR}/apps/"     "${CHROOT_DIR}/tmp/aurum/apps/"
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
#
# vm.swappiness=180: AurumOS uses a zram (compressed-RAM) swap device, not a
# slow disk swap. With zram, swapping is cheap, so a HIGH swappiness is correct
# — it lets the kernel move cold pages into compressed RAM and keep more file
# cache hot. (The old value of 0 was for disk swap and actively fought the zram
# device this distro configures, which is incoherent.) 180 is the value the
# kernel docs and Fedora/CachyOS recommend for zram-backed systems.
vm.swappiness = 180
# Reclaim dirty pages aggressively under a zram setup; pairs with swappiness.
vm.dirty_ratio = 10
vm.dirty_background_ratio = 5
vm.vfs_cache_pressure = 50
# Hugepages left at kernel default (0 static); THP stays "madvise" so DL
# allocators that ask for it get it without forcing it system-wide.
vm.nr_hugepages = 0
vm.max_map_count = 1600000
# numa_balancing only helps real multi-socket NUMA boxes; harmless elsewhere
# but the kernel ignores it on single-node systems, so leave it on.
kernel.numa_balancing = 1
net.core.wmem_max = 16777216
net.core.rmem_max = 16777216
EOF

    # Configure custom services (like disabling standard swap and setting up ZRAM via systemd)
    log_info "Configuring memory manager rules (ZRAM + Transparent HugePages)..."
    # Ship a helper that sizes zram to the MACHINE, not a hard-coded 32G. The old
    # unit reserved 32G of zram on every box — on a 16-32G laptop that can exhaust
    # RAM under memory pressure and OOM/freeze the system. We size it to
    # min(RAM/2, 16G): a compressed device that comfortably fits in RAM.
    install -d -m 0755 "${CHROOT_DIR}/usr/local/sbin"
    cat <<'SH' > "${CHROOT_DIR}/usr/local/sbin/aurum-zram-setup"
#!/usr/bin/env bash
# Size and activate a zram swap device proportional to physical RAM.
# Target: 50% of RAM, capped at 16 GiB. Disk swap is NOT used — zram only.
set -euo pipefail

modprobe zram num_devices=1 || true
DEV=/dev/zram0
SYS=/sys/block/zram0

# If a previous run left it active, reset before resizing.
if [[ -e "${SYS}/disksize" ]] && [[ "$(cat "${SYS}/disksize")" != "0" ]]; then
    swapoff "${DEV}" 2>/dev/null || true
    echo 1 > "${SYS}/reset" 2>/dev/null || true
fi

# Physical RAM in KiB → bytes, then 50% capped at 16 GiB.
ram_kib=$(awk '/^MemTotal:/ {print $2}' /proc/meminfo)
half_bytes=$(( ram_kib * 1024 / 2 ))
cap_bytes=$(( 16 * 1024 * 1024 * 1024 ))
size_bytes=$(( half_bytes < cap_bytes ? half_bytes : cap_bytes ))

echo zstd > "${SYS}/comp_algorithm" 2>/dev/null || true
echo "${size_bytes}" > "${SYS}/disksize"
mkswap "${DEV}" >/dev/null
# Priority 100 so zram is preferred over any disk swap that may exist.
swapon -p 100 "${DEV}"
echo "[aurum-zram] activated ${size_bytes} bytes (RAM-proportional, zstd)"
SH
    chmod 0755 "${CHROOT_DIR}/usr/local/sbin/aurum-zram-setup"

    cat <<EOF > "${CHROOT_DIR}/etc/systemd/system/aurum-zram.service"
[Unit]
Description=AurumOS ZRAM swap (RAM-proportional, zstd)
After=multi-user.target

[Service]
Type=oneshot
RemainAfterExit=yes
ExecStart=/usr/local/sbin/aurum-zram-setup
ExecStop=/sbin/swapoff /dev/zram0

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

# --- Wave 8/9: hardware profile + SOTA-2026 stack ----------------------------
# Order matters: profile detector runs first so every subsequent installer can
# `source /etc/aurum/profile.conf` to gate its install steps to the user's
# hardware tier (lite | standard | pro | workstation). The systemd unit
# regenerates the conf on every boot, so per-tier defaults follow the GPU.
install -d -m 0755 /etc/aurum
install -m 0755 /tmp/aurum/00-detect-profile.sh /usr/local/bin/aurum-detect-profile
bash /usr/local/bin/aurum-detect-profile
systemctl enable aurum-detect-profile.service || true

# Stage pinned per-domain pip requirements next to the venv (referenced by each
# installer via $PIP_REQS or hard-coded relative paths).
install -d -m 0755 /usr/local/share/aurum-os/pip-requirements
cp /tmp/aurum/pip-requirements-*.txt /usr/local/share/aurum-os/pip-requirements/

# Stage assets (LiteLLM proxy config, Langfuse compose, Continue.dev template)
install -d -m 0755 /etc/aurum
cp /tmp/aurum/assets/litellm-config.yaml /etc/aurum/litellm-config.yaml 2>/dev/null || true
install -d -m 0755 /opt/aurum-langfuse
cp /tmp/aurum/assets/langfuse-docker-compose.yml /opt/aurum-langfuse/docker-compose.yml 2>/dev/null || true
cp /tmp/aurum/assets/langfuse-env.template       /opt/aurum-langfuse/.env.template 2>/dev/null || true

# Run the per-domain installers. They are profile-aware — heavy tools (vLLM,
# ComfyUI, DeepSpeed) auto-skip on lower tiers.
bash /tmp/aurum/05-install-quantization.sh
bash /tmp/aurum/06-install-finetuning.sh
bash /tmp/aurum/07-install-llm-serving.sh
bash /tmp/aurum/08-install-llm-workflows.sh
bash /tmp/aurum/09-install-ai-coding.sh
bash /tmp/aurum/10-install-observability.sh
bash /tmp/aurum/11-install-cv-multimodal.sh
bash /tmp/aurum/12-install-model-pack-manager.sh

# Third-party app support: Flatpak + Flathub (sandboxed GUI apps).
bash /tmp/aurum/13-install-flatpak.sh

# Install all SOTA launchers + recipes system-wide.
install -d -m 0755 /usr/local/bin /usr/local/share/aurum-os/recipes
for t in aurum-finetune aurum-launch-vllm aurum-launch-sglang aurum-launch-tgi \
         aurum-launch-litellm aurum-launch-langfuse aurum-launch-phoenix \
         aurum-launch-comfyui aurum-launch-aider aurum-launch-claude-code \
         aurum-eval aurum-mcp-template \
         aurum-configure-continue.sh aurum-cv-download-models aurum-model-pack; do
    if [ -f "/tmp/aurum/tools/${t}" ]; then
        install -m 0755 "/tmp/aurum/tools/${t}" "/usr/local/bin/${t%.sh}"
    fi
done
# Python helper for the model-pack CLI (loaded by the bash shim)
install -d -m 0755 /usr/local/lib/aurum
[ -f /tmp/aurum/tools/aurum-model-pack-helpers.py ] && \
    install -m 0644 /tmp/aurum/tools/aurum-model-pack-helpers.py /usr/local/lib/aurum/

# --- System updater (client side) --------------------------------------------
# aurum-update: user-facing CLI (check/apply). The privileged apply helper goes
# to libexec and is reachable only through the polkit action, so the GUI/CLI
# can request an update without running the whole updater as root.
if [ -f /tmp/aurum/tools/aurum-update ]; then
    install -m 0755 /tmp/aurum/tools/aurum-update /usr/local/bin/aurum-update
fi
if [ -f /tmp/aurum/tools/aurum-update-apply ]; then
    install -d -m 0755 /usr/local/libexec
    install -m 0755 /tmp/aurum/tools/aurum-update-apply /usr/local/libexec/aurum-update-apply
fi
if [ -f /tmp/aurum/polkit/org.aurumos.update.policy ]; then
    install -d -m 0755 /usr/share/polkit-1/actions
    install -m 0644 /tmp/aurum/polkit/org.aurumos.update.policy \
        /usr/share/polkit-1/actions/org.aurumos.update.policy
fi

# --- CV training pipeline (point-cloud segmentation) -------------------------
# Python modules go to a shared dir; aurum-cv-train launcher to PATH. The DL
# stack (PyTorch + scikit-learn) is already installed by Phase 4.
if [ -d /tmp/aurum/cv-training ]; then
    install -d -m 0755 /usr/local/share/aurum-os/cv-training
    install -m 0644 /tmp/aurum/cv-training/*.py /usr/local/share/aurum-os/cv-training/ 2>/dev/null || true
    if [ -f /tmp/aurum/cv-training/aurum-cv-train ]; then
        install -m 0755 /tmp/aurum/cv-training/aurum-cv-train /usr/local/bin/aurum-cv-train
    fi
fi

# --- App icons → hicolor theme (so QIcon::fromTheme(<id>) resolves them) ------
# Fixes icon resolution for every distro/applications/*.desktop entry.
if [ -d /tmp/aurum/app-icons ]; then
    install -d -m 0755 /usr/local/share/icons/hicolor/256x256/apps
    install -m 0644 /tmp/aurum/app-icons/*.png \
        /usr/local/share/icons/hicolor/256x256/apps/ 2>/dev/null || true
    THEME=/usr/local/share/icons/hicolor/index.theme
    if [ ! -f "$THEME" ]; then
        cat > "$THEME" <<'ITHEME'
[Icon Theme]
Name=AurumOS
Comment=AurumOS native icons
Directories=256x256/apps

[256x256/apps]
Size=256
Type=Fixed
Context=Applications
ITHEME
    fi
    command -v gtk-update-icon-cache >/dev/null 2>&1 && \
        gtk-update-icon-cache -f -t /usr/local/share/icons/hicolor 2>/dev/null || true
fi
# Recipes go to a shared dir; user copies/symlinks into their projects.
rsync -a /tmp/aurum/recipes/ /usr/local/share/aurum-os/recipes/

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
    # In the ubuntu path the kernel/initrd were installed *inside* the chroot by
    # bootstrap_ubuntu; lift them into casper/ before squashing (and exclude
    # /boot from the squashfs so we don't ship the kernel twice).
    if [[ "${BASE_FLAVOR}" == "ubuntu" ]]; then
        log_info "Extracting kernel + initrd from chroot into casper/..."
        cp "${CHROOT_DIR}"/boot/vmlinuz-* "${ISO_DIR}/casper/vmlinuz"
        cp "${CHROOT_DIR}"/boot/initrd.img-* "${ISO_DIR}/casper/initrd"
    fi

    log_info "Recompressing SquashFS (zstd for fast load speed)..."
    rm -f "${ISO_DIR}/casper/filesystem.squashfs"
    local excl=()
    [[ "${BASE_FLAVOR}" == "ubuntu" ]] && excl=(-e boot)
    mksquashfs "${CHROOT_DIR}" "${ISO_DIR}/casper/filesystem.squashfs" \
        -comp zstd -b 1048576 -noappend "${excl[@]}"
    log_success "SquashFS rebuilt."
}

# Step 8: Build Custom ISO image
generate_iso() {
    log_info "Regenerating checksum files..."
    (cd "${ISO_DIR}" && find . -type f -not -name 'md5sum.txt' -not -path './isolinux/*' -exec md5sum {} + > md5sum.txt)

    mkdir -p "$(dirname "${OUTPUT_ISO}")"

    if [[ "${BASE_FLAVOR}" == "ubuntu" ]]; then
        # Self-contained path: write a GRUB config and let grub-mkrescue produce
        # a hybrid BIOS+UEFI ISO. This is the path validated to boot in QEMU.
        log_info "Writing GRUB config + generating hybrid ISO via grub-mkrescue..."
        cat > "${ISO_DIR}/boot/grub/grub.cfg" <<GRUB
set timeout=5
set default=0
insmod all_video
menuentry "AurumOS ${VERSION} (live)" {
    linux /casper/vmlinuz boot=casper quiet splash
    initrd /casper/initrd
}
menuentry "AurumOS ${VERSION} (live, safe graphics)" {
    linux /casper/vmlinuz boot=casper nomodeset
    initrd /casper/initrd
}
GRUB
        grub-mkrescue -o "${OUTPUT_ISO}" "${ISO_DIR}"
    else
        # Pop!_OS path: reuse the vendor's isolinux + EFI image layout.
        log_info "Generating hybrid ISO image via xorriso (Pop!_OS layout)..."
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
    fi

    log_success "Custom ISO built successfully: ${OUTPUT_ISO}"
}

# Master Flow execution
main() {
    case "${BASE_FLAVOR}" in
        ubuntu|popos) ;;
        *) log_error "Unknown --base '${BASE_FLAVOR}' (expected: ubuntu | popos)"; exit 1 ;;
    esac

    log_info "Building AurumOS v${VERSION} ISO (base: ${BASE_FLAVOR})"
    check_dependencies

    trap unmount_chroot EXIT INT TERM

    if [[ "${BASE_FLAVOR}" == "ubuntu" ]]; then
        bootstrap_ubuntu
    else
        get_base_iso
        extract_iso
    fi

    mount_chroot
    customize_system
    unmount_chroot

    rebuild_squashfs
    generate_iso
}

main
