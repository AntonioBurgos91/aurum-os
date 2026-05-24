# aurum-installer

Qt6/QML installer wizard. Wraps the Pop!_OS `distinst` CLI for the actual
disk imaging — we own the UX, distinst owns the heavy lifting.
See [`ADR-0005`](../../docs/adr/0005-installer-architecture.md) for the
rationale.

| File                    | Role                                         |
|-------------------------|----------------------------------------------|
| `main.cpp`              | Qt entry + QML context wiring                |
| `disk_lister.*`         | `lsblk -J` → filtered candidate disks        |
| `installer_backend.*`   | Builds + runs `distinst` via pkexec, parses progress |
| `Installer.qml`         | Linear StackView wizard                      |
| `pages/`                | Welcome / Locale / Disk / Account / Summary / Install / Done |
| `polkit/`               | Action `org.aurumos.installer.run`           |

v0.1.0-beta supports whole-disk installs only; custom partitioning is in
the post-1.0 roadmap.
