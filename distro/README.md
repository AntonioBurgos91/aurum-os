# AurumOS Distro Configuration & ISO Builder

This directory houses the tools, packages lists, seed configurations, and post-installation scripts required to generate the AurumOS installation ISO.

## Directory Structure
- [packages/](file:///home/develop/.gemini/antigravity/scratch/aurum-os/distro/packages) - Package lists for APT, uv, and system dependencies.
- [seed/](file:///home/develop/.gemini/antigravity/scratch/aurum-os/distro/seed) - Default user dotfiles and system configurations (e.g., Fish, Ghostty, Zellij configs).
- [post-install/](file:///home/develop/.gemini/antigravity/scratch/aurum-os/distro/post-install) - Custom overlay application scripts run inside the target squashfs filesystem.
- [iso-builder/](file:///home/develop/.gemini/antigravity/scratch/aurum-os/distro/iso-builder) - Scripts to fetch Pop!_OS base ISO, extract it, apply our customizations, and repackage it.

## Build Flow
1. Fetch base Pop!_OS 24.04 LTS ISO.
2. Mount and extract SquashFS.
3. Chroot and install `dl.list` and `system.list` packages.
4. Apply the `seed/` overlay for configuration files.
5. Apply kernel and driver tuning configs.
6. Regenerate initramfs and compile boot loader configurations.
7. Rebuild SquashFS and generate the customized hybrid ISO image.
