# AurumOS — Validation Status

_Last updated: 2026-06-04. This document records what has actually been
exercised vs. what remains unverified, so the project's maturity is not
overstated. A claim only moves to "verified" when it was observed working,
not when the code "looks correct."_

## Summary

AurumOS is a **solid beta**. The desktop, daemons, build tooling and the
generic install-and-boot mechanism are verified working. The project-specific
graphical installer (`distinst`), the real AI stack at runtime, and any
hardware diversity / real users remain unverified. Treat it as `0.x-beta`.

## Verified working (observed, not assumed)

- **Shell scripts** — 57 scripts, `shellcheck -S warning`, 0 issues.
- **Rust daemons** — clippy `-D warnings` 0 warnings; fmt clean; unit tests
  gpu-monitor 7/7, ml-jobs-tracker 11/11.
- **C++/Qt6 desktop** — clang-format clean; full build, all targets, 0 errors.
- **Desktop runtime** — 9 apps launch with 0 QML runtime errors (headless Wayland).
- **GPU telemetry** — real hardware read via D-Bus: `source_kind=amd-sysfs`,
  live utilization/temperature/VRAM on AMD Radeon.
- **Idle footprint** — desktop RAM at idle 323 MB (budget: <=600 MB).
- **AI-stack smoke** — Wave 8/9 harness 6 PASS / 0 FAIL (SKIP where stack absent).
- **ISO build** — `build.sh --base ubuntu` produces a hybrid BIOS+UEFI ISO.
- **Live ISO boot** — QEMU: GRUB -> kernel -> casper -> systemd -> login.
- **Installed-system boot** — disk install + UEFI boot in QEMU: OVMF -> GRUB ->
  systemd -> graphical.target -> login; the first-boot service ran and wrote a
  persistent marker to disk (confirms real persistence, not a live session).

## NOT yet verified (honest gaps)

### 1. The project's own graphical installer (distinst)
`aurum-installer` is a Qt6/QML wizard that shells out to Pop!_OS's `distinst`
backend (see ADR-0005). `distinst` is **not packaged in the Ubuntu archive** —
it ships only in Pop!_OS's repos — so the full graphical install path could not
be exercised here. What *was* verified is the **generic** install mechanism
(debootstrap rootfs -> partition -> GRUB EFI -> persistent UEFI boot), the same
end state `distinst` produces. The wizard UI and its `distinst` invocation
themselves remain untested end-to-end.
**To close:** run `aurum-installer` on a real Pop!_OS-based live ISO in a VM and
confirm it partitions, installs, and reboots into the desktop.

### 2. The real AI stack at runtime
The SOTA-2026 stack (PyTorch, vLLM, ComfyUI, DSPy, ...) is installed by the
`distro/post-install/*.sh` scripts, which were **never executed against a real
GPU/CUDA environment** here. The smoke tests confirm the *plumbing* (recipes,
templates, profile gating, config files) but SKIP the actual imports because
the libraries aren't installed in the CPU-only preview.
**To close:** on a CUDA (or ROCm) box, run the post-install scripts, then
`aurum-dl-verify` + `tests/dl_smoke.py` and confirm PyTorch sees the GPU and
vLLM serves a model.

### 3. Hardware diversity and real users
Everything has been observed on a single machine (AMD Ryzen 7 7730U, Radeon
iGPU). The NVIDIA path of `aurum-gpu-monitor` (NVML) compiles but was never
exercised on real NVIDIA hardware. There are zero external users.
**To close:** boot the installed system on at least one NVIDIA box and one
discrete-AMD box; gather feedback from >0 real users.

## Notes on the QEMU boot investigation

Legacy BIOS (SeaBIOS) boot of the installed disk image stalled at "Booting
from Hard Disk" in this sandbox, despite a valid MBR signature and an embedded
GRUB `core.img`. UEFI (OVMF) boot of the same system succeeded cleanly. This is
an environment/firmware interaction, not an AurumOS defect — the live ISO boots
under both. Real machines should prefer UEFI regardless.
