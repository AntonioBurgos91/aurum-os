# ADR 0005: Installer architecture

## Status
Accepted (Phase 6)

## Context
The Pop!_OS installer is a GTK-based Rust application invoking the `distinst`
backend. AurumOS needs a wizard whose UX matches the rest of the desktop
(Qt6/QML + Aurum.Aqua theme tokens) but should not reimplement disk imaging,
GRUB / systemd-boot installation, or locale provisioning — those are
well-trodden problems already solved upstream.

## Decision
Build `aurum-installer` as a thin Qt6/QML wizard whose backend shells out to
the `distinst` CLI for the actual install. The wizard:

- Collects user choices across 5 input pages (Welcome, Locale, Disk, Account,
  Summary).
- Constructs the `distinst --block ... --bootloader ... --filesystem ...`
  invocation.
- Spawns it via `pkexec` (polkit action `org.aurumos.installer.run`).
- Streams stdout/stderr into a log viewer and parses `STEP <NAME> <PERCENT>`
  lines into a progress bar.

The Phase 6 release ships **only whole-disk installs**. Custom partition
layouts are deferred — `distinst` supports them via a JSON descriptor, but
the wizard UX for partition editing is a project of its own.

## Consequences
- **Pros**
  - Reuses an audited, MIT-licensed installer backend with broad hardware
    coverage.
  - Wizard runs unprivileged; only distinst escalates.
  - bcachefs root is available out of the box (distinst ≥ 0.7).
- **Cons**
  - We track distinst's CLI surface; flag renames are breaking.
  - No partition editor for the v0.1 release.
- **Alternatives considered**
  - Calamares (Qt-based, well-documented, multi-distro) — rejected because
    its module system pushes its own UX conventions that would clash with
    Aurum.Aqua, and it carries a much larger transitive dep footprint
    (KDE Frameworks, qmlbox).
  - Hand-rolled installer in Rust — rejected on scope; we have no advantage
    over distinst's existing implementation.
