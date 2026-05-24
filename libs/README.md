# AurumOS Core Shared Libraries

This directory contains shared packages and system style modules reused across desktop components and tools.

## Subprojects
- **aqua-qt**: Custom Qt style engine that replicates macOS Sequoia UI styling (materials, vibrancy, shadow depths, borders). Installs SF Pro fonts mapping via Inter Display.
- **core-services**: C++/Rust bridge library handling D-Bus bindings, system notification posting, and common structures.
- **ml-integrations**: Integrations targeting MLflow, Weights & Biases API, local SQLite caching, and network fetch routines for HuggingFace / arXiv index queries.
