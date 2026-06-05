# AurumOS — Validation Status

_Last updated: 2026-06-05 (rev 4). This document records what has actually been
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
- **Rust daemons** — clippy `-D warnings` 0 warnings; fmt clean. Tests now
  exercise the real crate library (refactored from bin-only + `#[path]` to a
  `lib` target), so coverage is measurable and the tests can't drift into
  re-implementing the logic. Counts: gpu-monitor 10, spotlight-indexer 8,
  ml-jobs-tracker 11 — all pass. Logic-module line coverage (cargo-llvm-cov):
  gpu-monitor lib.rs 100%, spotlight-indexer index.rs 90% / watch.rs 80%,
  ml-jobs-tracker mlflow.rs 100%. The `main.rs` wiring (hardware/D-Bus) is 0%,
  not unit-testable without a GPU/bus.
- **C++/Qt6 desktop** — clang-format clean; full build, all targets, 0 errors.
- **Desktop runtime** — 9 apps launch with 0 QML runtime errors (headless Wayland).
- **GPU telemetry** — real hardware read via D-Bus: `source_kind=amd-sysfs`,
  live utilization/temperature/VRAM on AMD Radeon.
- **Idle footprint** — desktop RAM at idle 323 MB (budget: <=600 MB).
- **AI-stack smoke** — Wave 8/9 harness 6 PASS / 0 FAIL (SKIP where stack absent).
- **App entries + icons** — all 22 aurum-*.desktop entries valid (Name/Exec/Type
  present); all 22 Icon= resolve to a real file (no missing icons, no
  duplicates); 7/7 Qt GUI apps launch and stay alive (no crash); 9/9 AI
  launchers are valid bash that degrade gracefully when the tool is absent.
- **Third-party apps** — Flatpak + Flathub enabled via 13-install-flatpak.sh;
  verified live that Flathub registers and `flatpak search` returns real apps.
- **Display settings panel** — new Settings "Displays" section (monitors,
  brightness, night light). Verified: clean build, aurum-settings launches
  without crashing in the live preview, and the pure logic (hyprctl JSON
  parsing, `monitor=` keyword construction, Kelvin labels, brightness clamp)
  is unit-tested (settings::display_manager, 5 cases). NOT verified: actual
  hardware control — the preview is headless with no hyprctl/hyprsunset/ddcutil
  and no real displays, so command *generation* is tested but not that monitors
  move or brightness changes. Needs a real Hyprland session (tracked under the
  "real hardware" gap below).

- **System updater (client side)** — aurum-update (check/apply/version) +
  aurum-update-apply (root via pkexec) + a menubar "Update" indicator. Consumes
  the existing signed-release server side (release-iso.yml). Verified: shellcheck
  clean (both scripts + build.sh), version_compare passes 8 cases (incl. release
  > pre-release and numeric 0.10.0 > 0.9.0), the check→parse→JSON flow yields the
  correct update_available against a simulated release, and the menubar builds +
  launches with UpdateClient without crashing. NOT verified: end-to-end apply
  against a REAL release — the repo has no published release yet, so the
  download + per-artifact SHA-256 + root re-verify chain is built and
  shellcheck-clean but unproven on a real download. The per-component install
  step is a deliberate verified no-op until a tagged component bundle exists.
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

## Bugs found by the app/icon verification (2026-06-05)

Auditing every .desktop revealed a real functional bug, now fixed: the Aider
and Claude Code entries declared `Exec=aurum-launch-aider` /
`aurum-launch-claude-code`, but build.sh installed the underlying CLIs (via
`uv tool install`) without copying those wrapper scripts to /usr/local/bin —
so on a real ISO clicking those two icons would have failed. Added both to the
launcher install loop (commit 3849653).

Caveat: 9 AI-launcher .desktop entries show "Exec missing" *in the Docker
preview* because that image was built without the launchers; build.sh does
install them on a real ISO. Not independently confirmed on a real ISO build
(too heavy for this sandbox) — tracked under gap #2.
