# Changelog

All notable changes to AurumOS. Format derived from "Keep a Changelog";
versioning follows [ADR-0007](docs/adr/0007-release-process.md).

## [0.1.0-beta] — 2026-05

### Added — Phase 1: Compositor + theme
- AurumOS Hyprland fork model (pinned `v0.46.2` + `aurum.conf` + `patches/`),
  built by [distro/iso-builder/build-hyprland.sh](distro/iso-builder/build-hyprland.sh).
- macOS-mapped keybindings, screenshot/cliphist, multimedia keys, layer-aware
  reserved space for the top/bottom strips.
- WhiteSur GTK + icon + cursor stack via [themes/install_themes.sh](themes/install_themes.sh).
- swww-first wallpaper engine with swaybg fallback + solid-color last resort.

### Added — Phase 2: Dock + menubar
- `aurum-dock` with magnification (Gaussian falloff to neighbors),
  `.desktop` launcher discovery, real `QProcess` exec.
- `aurum-menubar` with live GPU/VRAM/temp applets and `hyprctl` focused-app
  reporter.
- `gpu-monitor` Rust daemon (NVML → D-Bus) + systemd user unit.
- `core-services`: XDG `.desktop` scanner and launcher.
- `aqua-qt`: Fusion-based palette + `Aurum.Aqua` QML module (`Theme`,
  `GlassPanel`, `MetricBadge`, `TrafficLights`).

### Added — Phase 3: Finder + Spotlight
- `aurum-spotlight-indexer` Rust daemon (tantivy + inotify, debounced commits).
- `aurum-finder` with ML sidebar (`~/datasets`, `~/models`, `~/notebooks`)
  and Quick Look for `.ipynb` / `.safetensors` / `.parquet`.
- `aurum-spotlight` overlay with five in-process plugins: Applications,
  Files, Calculator, Hugging Face, arXiv.

### Added — Phase 4: DL stack
- `02-install-dl-stack.sh` driven by `pip-requirements.txt` as the single
  source of truth (replaced the dl.list regex hack).
- `03-install-llm-runtimes.sh` for Ollama + LM Studio CLI wrapper.
- `.desktop` entries for JupyterLab, Marimo, Ollama, LM Studio.
- `tests/dl_bench.py` (matmul + H2D bandwidth) and `aurum-dl-verify` wrapper.

### Added — Phase 5: Settings + MLOps
- `aurum-settings` with five sections: General, GPU, CUDA, Python Venvs, MLOps.
- CUDA manager (per-user env file + pkexec system-wide symlink switch via
  polkit policy `org.aurumos.settings.cuda-switch`).
- uv-driven venv manager with system-locked safety check.
- MLOps `~/.config/aurum/mlops.toml` reader/writer.
- `ml-jobs-tracker` Rust daemon polling MLflow REST API.
- `aurum-mission-control` overlay (workspace + window grid via `hyprctl`).
- `uv` symlinked system-wide (`/usr/local/bin/uv`).

### Added — Phase 6: Polish + release
- `aurum-installer` Qt6/QML wizard wrapping the `distinst` backend.
- `04-perf-tune.sh`: boot + idle tuning (service masking, kernel cmdline,
  systemd timeouts).
- `tests/boot_bench.sh` + `tests/idle_bench.sh` gating the budget
  ([ADR-0006](docs/adr/0006-performance-budget.md)).
- Updated CI workflow (pip-requirements.txt-driven, Rust build added,
  shellcheck/py_compile linting).
- `.github/workflows/release.yml` for tagged ISO + lockfile bundle publishing.
- ADRs 0005 / 0006 / 0007.
- User guides: dl-quickstart, cuda-management, spotlight-plugins, troubleshooting.

### Fixed during pre-beta verification pass
10 bugs surfaced only by runtime testing (none would have been caught by
compile-time checks alone):

1. **zbus 4 PascalCase auto-rename** — daemons exposed `Stats` / `GpuName`
   etc. on the wire; C++ clients called `stats` / `gpu_name`. 100 % silent
   runtime failure. Pinned wire names with `#[zbus(name = "...")]` on 13
   methods across all three daemons.
2. **`pip-requirements.txt` `torch==2.5.1`** wasn't resolvable on Python 3.13
   (no torchvision in the cp313 ABI lineage pairs with 2.5.1). Floated to
   `torch>=2.7,<3`.
3. **Qt6 runtime QML plugins missing** from `Dockerfile` + `system.list` —
   only the `-dev` headers were installed. Every `import QtQuick.Controls`
   would have failed silently in production. Added `qml6-module-*`.
4. **`/opt/aurum-dl-venv` permissions** — venv created by root with default
   mode left users unable to access `bin/python`. Added `chmod -R a+rX` in
   `02-install-dl-stack.sh`.
5. **spotlight-indexer D-Bus bind order** — daemon registered on the bus
   only AFTER the initial crawl finished, so cold boot showed a 15+ s
   "daemon doesn't exist" window. Refactored to bind first, crawl via
   `tokio::task::spawn_blocking`.
6. **Cargo.lock not committed** — violated ADR-0007 reproducibility promise.
   Generated + committed for all three Rust daemons.
7. **`fs.inotify.max_user_watches` not bumped** — kernel default 524 288
   would have broken Spotlight on real ML workspaces. Added a `sysctl.d`
   drop-in in `04-perf-tune.sh` raising it to 2 097 152.
8. **`importlib.util` not auto-imported on Python 3.13** in
   `02-install-dl-stack.sh::install_packages`. Sanity check died with
   `AttributeError`. Fixed with explicit `import importlib.util`.
9. **`init_*()` helpers wrote to stdout**, contaminating the output of tools
   that pipe library results (e.g. `aurum-test-preview` → `json.tool`).
   Moved to stderr.
10. **`02-install-dl-stack.sh` `--no-cache` hardcoded** caused uv to
    re-download wheels indefinitely in CI. Now controlled via `UV_NO_CACHE`
    env (default `1` for production, `0` for CI).

### Known gaps in this release
- The dock uses placeholder icon chips when an icon doesn't resolve via the
  XDG theme (themed icons cache works for valid names).
- File open from Finder on non-directory entries is read-only (no MIME
  handler dispatch); planned for v0.2.
- Mission Control takes a snapshot of `hyprctl clients` at open time and
  doesn't refresh from the live event stream. Acceptable for v0.1.
- LM Studio AppImage is **not bundled**; the `lms` CLI wrapper bootstraps
  on first use only if the user installs the desktop AppImage.
- TensorFlow + cryptography wheel skew (`X509_V_FLAG_NOTIFY_POLICY`) is an
  upstream issue; `aurum-dl-verify` reports it without crashing, and the
  troubleshooting guide documents the workaround.
