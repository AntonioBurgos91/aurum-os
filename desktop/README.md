# AurumOS Desktop Environment (DE)

The AurumOS desktop environment delivers a premium macOS Sequoia UX while remaining extremely light on resources. Components are implemented using **C++23** and **Qt 6.8 / QML**, using Wayland exclusively through a custom minimal fork of **Hyprland** (rather than a heavy Vulkan-based compositor) to conserve precious GPU VRAM for machine learning workloads.

## Components
- **dock/**: Docking area featuring application magnification, status badges, and an integrated GPU load indicator.
- **menubar/**: Global top bar supporting status indicators (VRAM, system performance, active training jobs via MLflow integration, network throughput).
- **finder/**: Core filesystem explorer with a specialized sidebar (quick access to `~/datasets`, `~/models`, `~/notebooks`, `~/experiments`) and custom metadata inspector/Quick Look.
- **spotlight/**: Intelligent overlay search supporting files (via Rust/Tantivy), local model tags, HuggingFace repository searching, and arXiv paper lookups.
- **mission-control/**: Overview window switcher.
- **notifications/**: Widget integration for active background deep learning training tasks.
- **settings/**: Control panel with modules for GPU power settings, CUDA version management, and Python virtual environment (uv) integration.
