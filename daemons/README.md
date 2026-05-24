# AurumOS Rust System Daemons

Background daemons in AurumOS are built with Rust to ensure safety, low overhead, and high concurrency. These services handle critical background tasks, system metrics collection, and inter-process communication.

## Core Daemons
- **spotlight-indexer**: Uses `inotify` and the `tantivy` search engine to perform real-time local indexing of documents, code (via tree-sitter symbols), `.ipynb` notebooks, and local model metadata.
- **gpu-monitor**: Collects real-time telemetry (utilization, VRAM, thermal limits, power states) and broadcasts updates via D-Bus for the MenuBar and Dock applets.
- **ipc-broker**: Provides a lightweight IPC broker to coordinate messages between desktop modules and backends.
- **ml-jobs-tracker**: Monitors local or remote training jobs by querying MLflow / Weights & Biases endpoints and updates the notification tray widget.
