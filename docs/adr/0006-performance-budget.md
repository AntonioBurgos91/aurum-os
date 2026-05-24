# ADR 0006: Performance budget

## Status
Accepted (Phase 6)

## Context
AurumOS targets workstations whose GPU is doing the real work. The desktop
must not visibly steal cycles or VRAM. We therefore commit to two hard
numbers and gate every release behind them.

## Budget

| Metric                              | Budget           | How verified                                    |
|-------------------------------------|------------------|-------------------------------------------------|
| Cold boot to graphical session      | **≤ 3.0 s**      | `tests/boot_bench.sh` parses `systemd-analyze`  |
| Idle RAM (desktop only, no user app)| **≤ 600 MB**     | `tests/idle_bench.sh` sums PSS via `/proc`      |
| Compositor frame rate at idle       | **60 fps**       | Hyprland `debug:overlay` + frame log audit      |
| Input → on-screen reaction          | **≤ 16 ms**      | Hyprland's built-in latency reporter            |

The budget excludes:
- Time spent in the initramfs unlocking LUKS (interactive).
- RAM held by the DL venv after it's been warm-imported (deliberate side-effect
  of `aurum-dl-verify` first-run; users can revert with `sync && echo 3 > /proc/sys/vm/drop_caches`).

## Decision
- Mask the services listed in [04-perf-tune.sh](../../distro/post-install/04-perf-tune.sh)
  (bluetooth, cups, snapd, avahi, ModemManager, apport, the apt timers).
- Use `nowatchdog` and `nvidia-drm.modeset=1` on the kernel command line.
- `GRUB_TIMEOUT=0` with `GRUB_TIMEOUT_STYLE=hidden`.
- Disable Hyprland blur and animations by default (`/etc/aurum/hypr/aurum.conf`).
- Boot benchmark runs on every release-tagged build; missing the budget fails
  the release pipeline.

## Consequences
- **Pros** — Predictable bring-up time; the dock/menubar feel instant.
- **Cons** — Users who want bluetooth must `systemctl unmask bluetooth.service`
  manually. Documented in [docs/guides/troubleshooting.md](../guides/troubleshooting.md).
- **Alternatives considered**
  - Plymouth + animated splash: rejected — adds ~250 ms to the critical chain
    and contributes nothing to a single-user workstation.
  - Pre-rendering Qt QML caches at first boot to cut first-launch latency:
    deferred — saves ~70 ms per app launch but adds first-boot complexity.
