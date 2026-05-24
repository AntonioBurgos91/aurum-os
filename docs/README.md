# AurumOS Documentation

This directory is the entry point for everything documented about AurumOS:
the architectural rationale (ADRs), end-user and developer guides, and a
top-level system overview. Per-component contracts live in the README of
each top-level subdirectory of the repo (`desktop/`, `daemons/`,
`libs/`, …).

## Where to start

| If you want to…                                       | Read                                                                                           |
|-------------------------------------------------------|------------------------------------------------------------------------------------------------|
| Install AurumOS on real hardware                      | [`guides/install-baremetal.md`](guides/install-baremetal.md)                                   |
| Pick the right NVIDIA driver for your GPU             | [`guides/nvidia-driver-matrix.md`](guides/nvidia-driver-matrix.md)                             |
| Understand how the system fits together               | [`architecture.md`](architecture.md)                                                           |
| See what the desktop looks like                       | [Screenshot gallery](../distro/demo/screenshots/README.md)                                     |
| Know why we made a specific technical choice          | [`adr/`](adr/) (see index below)                                                               |
| Get started with the DL stack post-install            | [`guides/dl-quickstart.md`](guides/dl-quickstart.md)                                           |
| Switch CUDA toolkits per-project                      | [`guides/cuda-management.md`](guides/cuda-management.md)                                       |
| Write a custom Spotlight plugin                       | [`guides/spotlight-plugins.md`](guides/spotlight-plugins.md)                                   |
| Diagnose something that broke                         | [`guides/troubleshooting.md`](guides/troubleshooting.md)                                       |

## Contents

### Architecture

- [`architecture.md`](architecture.md) — system overview with Mermaid
  diagrams of components, D-Bus signal flow, boot sequence, build
  pipeline, and state locations.

### Architecture Decision Records ([`adr/`](adr/))

1. [`0001-base-operating-system.md`](adr/0001-base-operating-system.md) — why Pop!_OS 24.04 LTS
2. [`0002-desktop-environment-architecture.md`](adr/0002-desktop-environment-architecture.md) — Qt6 + Hyprland + session D-Bus
3. [`0003-package-management.md`](adr/0003-package-management.md) — apt + system venv layout
4. [`0004-memory-and-storage.md`](adr/0004-memory-and-storage.md) — defaults for disk and swap
5. [`0005-installer-architecture.md`](adr/0005-installer-architecture.md) — `aurum-installer` design
6. [`0006-performance-budget.md`](adr/0006-performance-budget.md) — idle CPU/RAM caps
7. [`0007-release-process.md`](adr/0007-release-process.md) — versioning and tagging

### Guides ([`guides/`](guides/))

- [`install-baremetal.md`](guides/install-baremetal.md) — full bare-metal install walkthrough
- [`nvidia-driver-matrix.md`](guides/nvidia-driver-matrix.md) — GPU family ↔ driver ↔ CUDA matrix
- [`dl-quickstart.md`](guides/dl-quickstart.md) — first project after install
- [`cuda-management.md`](guides/cuda-management.md) — running multiple CUDA toolkits
- [`spotlight-plugins.md`](guides/spotlight-plugins.md) — built-in plugins + authoring a new one
- [`troubleshooting.md`](guides/troubleshooting.md) — common breakage and fixes

### Visual reference

- [Screenshot gallery](../distro/demo/screenshots/README.md) — milestone-by-milestone visual log.
  Latest reference: `aurum-ORCHESTRATED-FINAL.png` (52/52 smoke pass).

## Conventions

- ADRs follow the standard "Context / Decision / Consequences" template.
  New ADRs get the next number and are appended to the index above.
- Guides are written for the user persona named in the table at the top
  of each file — keep the audience tight.
- Mermaid diagrams in Markdown are preferred over external image files
  so they stay reviewable in `git diff`.
