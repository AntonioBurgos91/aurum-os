# ADR 0003: Package Management Strategy

## Status
Approved

## Context
Deep Learning environments traditionally rely on Conda or Anaconda to isolate Python interpreters and libraries. However, Conda is notoriously slow at resolving dependencies, bloats the system storage, and lacks native integrations with modern fast tools. Additionally, runtime engines for other languages (Node.js, Go) must be managed cleanly without polluting the base OS packages.

## Decision
1. Retain **APT** for base system libraries.
2. Use **`uv`** (written in Rust) as the primary package manager for all Python runtimes and libraries.
3. Use **`mise`** to manage developer runtimes (Node, Go, Ruby, etc.).
4. Develop **`osbrew`** (a custom terminal UI) as a unified homebrew-like frontend wrapper.

## Consequences
- **Pros**:
  - `uv` is up to 100x faster than standard `pip` or `conda` at resolving dependencies and installing wheels.
  - Keeps system dependencies cleanly separated from ML dependencies inside isolated, fast virtualenvs.
  - `mise` provides rapid, lightweight shim execution for global node/go binaries.
- **Cons**:
  - Users familiar with `conda create -n env` must learn `uv venv` workflows (mitigated by system documentation).
- **Alternative considered**: Conda / Miniconda. Rejected due to poor execution speed and memory-heavy resolver.
