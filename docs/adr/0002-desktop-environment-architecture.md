# ADR 0002: Desktop Environment Architecture

## Status
Approved

## Context
Standard desktop environments (such as GNOME, KDE, or Apple-clones like Cosmic) often run heavy compositor animations, shell integrations, or Electron-based plugins that consume significant GPU memory (VRAM). For deep learning engineers, GPU memory is a scarce resource. However, users still desire a cohesive, premium macOS Sequoia-like UX.

## Decision
We will build a custom desktop environment using a lightweight, minimal fork of **Hyprland** (Wayland-exclusive) as the window compositor, combined with standalone UI modules (`aurum-dock`, `aurum-menubar`, `aurum-spotlight`, `aurum-finder`) built in **C++23** and **Qt 6.8 / QML** with the **aqua-qt** theme engine.

## Consequences
- **Pros**:
  - Wayland-native rendering with extremely low CPU/GPU overhead.
  - Idle RAM target of <600MB.
  - Keeps precious GPU VRAM free for tensor execution (animations and effects do not compete with PyTorch/vLLM).
  - High performance C++23 application execution.
- **Cons**:
  - Requires maintaining custom C++/Qt panels and dock logic instead of reusing standard widgets.
  - X11 backward compatibility runs through XWayland, which must be configured securely.
- **Alternative considered**: Custom Vulkan-based compositor from scratch. Rejected due to high engineering complexity and potential VRAM collision with compute frameworks.
