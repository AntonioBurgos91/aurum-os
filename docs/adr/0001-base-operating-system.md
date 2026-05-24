# ADR 0001: Base Operating System Selection

## Status
Approved

## Context
Developing a production-ready Linux distribution from scratch for deep learning is a massive undertaking. Packages like NVIDIA drivers, CUDA toolkits, cuDNN, container execution stacks, and display drivers require constant packaging, testing, and upkeep. We require a stable, Ubuntu-compatible core to benefit from wide tool support while ensuring deep learning developers get stable out-of-the-box configurations.

## Decision
We will fork and build upon **Pop!_OS 24.04 LTS**.

## Consequences
- **Pros**:
  - Leverages System76's existing driver management (e.g., custom Linux kernels with scheduler patches).
  - Pre-packages current stable NVIDIA proprietary/open GPU drivers and CUDA runtimes.
  - Full compatibility with Ubuntu LTS repositories, software installers, and standard libraries.
  - Built-in kernel-level toggles for system-wide performance modes.
- **Cons**:
  - Requires stripping the GNOME-based COSMIC desktop environment (replaced by our C++23/Qt6 DE to save VRAM).
  - Inherits Ubuntu's package updates lag (partially mitigated by compiling critical DE libs/daemons and using uv/mise).
- **Alternative considered**: Ubuntu 24.04 LTS (Vanilla). Denied due to lack of standard out-of-the-box driver select tooling and kernel scheduling optimizations.
