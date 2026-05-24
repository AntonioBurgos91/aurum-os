# AurumOS

[![CI](https://github.com/aurumos/aurum-os/actions/workflows/ci.yml/badge.svg?branch=main)](.github/workflows/ci.yml)
[![License: GPL v3+](https://img.shields.io/badge/License-GPL_v3+-blue.svg)](LICENSE)
[![Smoke Tests](https://img.shields.io/badge/smoke--tests-52%2F52-brightgreen.svg)](tools/smoke-test.sh)
[![Version](https://img.shields.io/badge/version-0.1.0--beta-orange.svg)](VERSION)

AurumOS is a production-ready Linux distribution optimized for programming,
deep learning, and AI model training/inference. The desktop experience
(UX/UI) is inspired by macOS Sequoia; the underlying architecture is tuned
for high-performance GPU workflows.

Built as a custom fork of **Pop!_OS 24.04 LTS** to inherit its out-of-the-box
CUDA support and optimized kernels, with a bespoke Qt6/QML desktop on top of
a pinned Hyprland fork so the compositor stays out of the GPU's way.

Current release: see [`VERSION`](VERSION) — [`CHANGELOG.md`](CHANGELOG.md)
for what shipped phase-by-phase.

## Repository layout

```
aurum-os/
├── distro/                # Pop!_OS ISO builder + overlays
│   ├── packages/          # apt + pip package lists (single source of truth)
│   ├── seed/              # Default dotfiles (→ /etc/skel/.config/)
│   │   ├── hypr/          # Hyprland config + wallpaper.sh engine
│   │   ├── ghostty/       # Terminal config
│   │   ├── fish/          # Shell config
│   │   └── wallpapers/    # → /usr/share/backgrounds/aurumos/ (NOT a dotfile)
│   ├── post-install/      # 01..04 numbered installers run in chroot
│   ├── applications/      # System-wide .desktop entries (→ /usr/share/applications)
│   ├── hyprland-fork/     # AurumOS Hyprland config + patches/ (Phase 1)
│   └── iso-builder/       # build.sh + build-hyprland.sh
├── desktop/               # Qt6/QML desktop environment (C++23)
│   ├── dock/              # Bottom dock w/ macOS-style magnification
│   ├── menubar/           # Top strip with live DL metrics
│   ├── finder/            # File manager + ML sidebar + Quick Look
│   ├── spotlight/         # Overlay + 5 in-process plugins
│   ├── mission-control/   # Workspace + window grid (hyprctl IPC)
│   ├── notifications/     # Tray stub (mako covers the role in v0.1)
│   ├── settings/          # 5-section settings panel
│   └── installer/         # Live-ISO wizard wrapping `distinst` (Phase 6)
├── daemons/               # Rust services (session D-Bus)
│   ├── gpu-monitor/       # NVML → D-Bus telemetry
│   ├── spotlight-indexer/ # tantivy + inotify index
│   ├── ml-jobs-tracker/   # MLflow REST → D-Bus
│   └── ipc-broker/        # Deferred — D-Bus is the broker for v0.1
├── libs/                  # Shared C++ libraries
│   ├── aqua-qt/           # Tokens, palette, Fusion init + Aurum.Aqua QML module
│   ├── core-services/     # XDG .desktop scanner + launcher
│   └── ml-integrations/   # Quick Look for .ipynb / .safetensors / .parquet
├── apps/
│   └── terminal-tweaks/   # AurumOS Zellij layout + cross-refs to seed/
├── themes/
│   ├── gtk4/              # WhiteSur fork delta (empty in v0.1)
│   ├── icons/             # Icon overrides (empty in v0.1)
│   └── install_themes.sh  # Pulls + builds WhiteSur GTK/icons/cursors
├── kernel-tuning/         # sysctl / udev / scheduler profiles
├── scripts/               # Out-of-process helpers (parquet_peek.py, …)
├── tests/                 # Smoke + benchmarks + acceptance harness
├── ci/                    # Self-hosted runner notes
├── docs/                  # ADRs + user guides
│   ├── adr/               # 0001..0007 architecture decision records
│   └── guides/            # dl-quickstart, cuda-management, …
├── .github/workflows/     # CI + release pipelines
├── CMakeLists.txt         # Superbuild root (Qt6 + Vulkan + wlroots)
├── Dockerfile             # Dev container (matches the chroot toolchain)
├── VERSION                # Single source of truth for the release tag
└── CHANGELOG.md           # Phase-by-phase release notes
```

Every subdirectory has its own `README.md`. Start there for the contracts
and the rationale.

## Quickstart

```bash
# Dev container
docker build -t aurumos:dev .
docker run --rm -it -v $(pwd):/workspace aurumos:dev bash

# Build the desktop (inside the container)
cmake -S . -B build -DCMAKE_BUILD_TYPE=Release
cmake --build build -j$(nproc)

# Build a fresh ISO (host needs root + loop devices)
sudo distro/iso-builder/build.sh -o build/aurumos.iso
```

## Verification

The acceptance criteria for v0.1.0-beta are gated by:

- [`tests/boot_bench.sh`](tests/boot_bench.sh) — boot ≤ 3 s
- [`tests/idle_bench.sh`](tests/idle_bench.sh) — idle RAM ≤ 600 MB
- [`tests/dl_smoke.py`](tests/dl_smoke.py) + [`tests/dl_bench.py`](tests/dl_bench.py) — DL stack
- [`tests/acceptance.sh`](tests/acceptance.sh) — runs all three and writes JSON reports

The installed system ships `aurum-acceptance` (the wrapper above) in `PATH`.

## CI / Tests

[![CI](https://github.com/aurumos/aurum-os/actions/workflows/ci.yml/badge.svg?branch=main)](.github/workflows/ci.yml)

Every push and pull request against `main` triggers the
[`CI`](.github/workflows/ci.yml) workflow, which runs in five stages on
GitHub-hosted `ubuntu-24.04` runners:

1. **lint-shell** — `shellcheck -S warning` across every tracked `*.sh`.
2. **lint-cpp** — `clang-format --dry-run --Werror` against `desktop/` + `libs/`,
   driven by the root [`.clang-format`](.clang-format).
3. **lint-rust** — `cargo fmt --check` and `cargo clippy -D warnings`
   for every Rust daemon + `tools/aurum-mockup`, with
   [`rustfmt.toml`](rustfmt.toml) as the source of truth.
4. **build-rust** + **build-cpp** — release builds with `Swatinem/rust-cache`
   and the full Qt6 toolchain; runs `cargo test` and `ctest --output-on-failure`.
5. **smoke** — boots the demo container
   (`distro/demo/Dockerfile.desktop`) and runs the 52-check
   [`tools/smoke-test.sh`](tools/smoke-test.sh) harness, uploading
   `smoke-output.json` as an artifact.

Tagging `v*` triggers [`.github/workflows/release.yml`](.github/workflows/release.yml),
which builds the ISO, computes `SHA256SUMS`, and publishes a draft GitHub Release.

Run the smoke suite locally with:

```bash
./tools/smoke-test.sh          # human-readable
./tools/smoke-test.sh --json   # machine-readable, same exit code
```

Optional local git hooks (`shellcheck`, `clang-format`, `cargo fmt`,
trailing-whitespace, large-file guard) are wired through
[`.pre-commit-config.yaml`](.pre-commit-config.yaml) — install with
`pip install pre-commit && pre-commit install`.

## License

AurumOS is licensed under the **GNU General Public License v3.0 or
later** (`GPL-3.0-or-later`). The full text is in [`LICENSE`](LICENSE)
(with a Debian-style [`COPYING`](COPYING) symlink for packaging
convenience). This license is required for compatibility with the
upstream Pop!_OS desktop components from which several AurumOS apps
derive.
