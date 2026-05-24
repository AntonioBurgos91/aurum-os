# AurumOS developer container.
# Base: Ubuntu 24.04 LTS — matches Pop!_OS 24.04 LTS so apt-resolvable libraries
# line up between dev and the target ISO chroot.
FROM ubuntu:24.04

ENV DEBIAN_FRONTEND=noninteractive

# ----------------------------------------------------------------------------
# Core toolchain — apt packages
# ----------------------------------------------------------------------------
RUN apt-get update && apt-get install -y --no-install-recommends \
        build-essential cmake meson ninja-build \
        git curl wget ca-certificates pkg-config sudo gnupg \
        software-properties-common \
        # Modern compilers (need GCC ≥ 14 for full C++23)
        gcc-14 g++-14 clang-18 clang-tools-18 lld-18 llvm-18 \
        # Wayland / wlroots stack consumed by libs/aqua-qt + future compositor work
        libwayland-dev wayland-protocols libegl1-mesa-dev libgbm-dev \
        libinput-dev libxkbcommon-dev libpixman-1-dev libudev-dev \
        libseat-dev libdisplay-info-dev libliftoff-dev libwlroots-dev \
        # Vulkan loader / tools
        libvulkan-dev vulkan-tools vulkan-utility-libraries-dev \
        # Qt 6.8 stack — every desktop binary + ml-integrations + the runtime
        # QML plugins (the `qml6-module-*` packages provide the .so plugins
        # the apps load when they `import QtQuick.Controls` etc.).
        qt6-base-dev qt6-declarative-dev qt6-wayland-dev qt6-multimedia-dev \
        qt6-l10n-tools libqt6svg6-dev \
        qml6-module-qtquick qml6-module-qtquick-controls \
        qml6-module-qtquick-layouts qml6-module-qtquick-window \
        qml6-module-qtquick-dialogs qml6-module-qtquick-templates \
        qml6-module-qtqml qml6-module-qtqml-workerscript \
        qml6-module-qtqml-models \
        # Hyprland build deps (used by distro/iso-builder/build-hyprland.sh)
        libcairo2-dev libpango1.0-dev libdrm-dev libgles2-mesa-dev \
        libxcb-composite0-dev libxcb-ewmh-dev \
        libxcb-icccm4-dev libxcb-render-util0-dev libxcb-res0-dev \
        libxcb-xinput-dev libxcb-util-dev libxkbcommon-x11-dev \
        libxcursor-dev libtomlplusplus-dev libzip-dev librsvg2-dev hwdata \
        # Shell + Python helpers (lint + tests)
        shellcheck python3 python3-pip \
    && rm -rf /var/lib/apt/lists/*

# GCC-14 / Clang-18 as the alternatives default. Some upstream Hyprland
# patches still assume `gcc` and `clang` resolve to a fresh compiler.
RUN update-alternatives --install /usr/bin/gcc gcc /usr/bin/gcc-14 100 \
        --slave /usr/bin/g++ g++ /usr/bin/g++-14 \
    && update-alternatives --install /usr/bin/clang clang /usr/bin/clang-18 100 \
        --slave /usr/bin/clang++ clang++ /usr/bin/clang++-18

# ----------------------------------------------------------------------------
# Rust toolchain — for daemons/{gpu-monitor,spotlight-indexer,ml-jobs-tracker}
# ----------------------------------------------------------------------------
ENV RUSTUP_HOME=/usr/local/rustup \
    CARGO_HOME=/usr/local/cargo \
    PATH=/usr/local/cargo/bin:$PATH
RUN curl --proto '=https' --tlsv1.2 -sSf https://sh.rustup.rs \
      | sh -s -- -y --default-toolchain stable \
    && chmod -R a+w "$RUSTUP_HOME" "$CARGO_HOME" \
    && rustc --version && cargo --version

# ----------------------------------------------------------------------------
# uv — Python package manager used by all DL installers.
# UV_INSTALL_DIR drops the binary system-wide so devs running the container
# without going through 02-install-dl-stack.sh still get the same uv.
# ----------------------------------------------------------------------------
ENV UV_INSTALL_DIR=/usr/local/bin
RUN curl -LsSf https://astral.sh/uv/install.sh | sh

# ----------------------------------------------------------------------------
# Defaults
# ----------------------------------------------------------------------------
ENV CC=clang CXX=clang++

RUN useradd -m -s /bin/bash developer \
    && echo "developer ALL=(ALL) NOPASSWD:ALL" >> /etc/sudoers

USER developer
WORKDIR /workspace
RUN mkdir -p /home/developer/.config/fish

CMD ["/bin/bash"]
