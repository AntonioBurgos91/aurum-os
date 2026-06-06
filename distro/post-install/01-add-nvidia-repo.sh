#!/usr/bin/env bash
# Adds NVIDIA developer repo for CUDA 12.8+, cuDNN, TensorRT, NCCL (Blackwell-ready)
# Run inside chroot during ISO build, before apt-get install -y < dl.list
set -euo pipefail

# --- Hardware guard (AMD-lite addition) -------------------------------------
if ! command -v nvidia-smi >/dev/null 2>&1 \
   && ! lspci 2>/dev/null | grep -qi 'nvidia'; then
    echo "[01-nvidia] no NVIDIA hardware detected — skipping CUDA repo setup"
    exit 0
fi

DISTRO="ubuntu2404"
ARCH="x86_64"

# CUDA repo (Pop!_OS 24.04 is Ubuntu 24.04 compatible)
wget -qO /tmp/cuda-keyring.deb \
  "https://developer.download.nvidia.com/compute/cuda/repos/${DISTRO}/${ARCH}/cuda-keyring_1.1-1_all.deb"
dpkg -i /tmp/cuda-keyring.deb
rm /tmp/cuda-keyring.deb

# NVIDIA Container Toolkit repo
curl -fsSL https://nvidia.github.io/libnvidia-container/gpgkey | \
  gpg --dearmor -o /usr/share/keyrings/nvidia-container-toolkit-keyring.gpg
curl -s -L https://nvidia.github.io/libnvidia-container/stable/deb/nvidia-container-toolkit.list | \
  sed "s#deb https://#deb [signed-by=/usr/share/keyrings/nvidia-container-toolkit-keyring.gpg] https://#g" \
  > /etc/apt/sources.list.d/nvidia-container-toolkit.list

apt-get update
echo "✓ NVIDIA repos añadidos: CUDA, cuDNN, TensorRT, NCCL, Container Toolkit"
