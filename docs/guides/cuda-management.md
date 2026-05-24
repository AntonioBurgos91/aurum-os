# CUDA toolkit management

AurumOS can hold several CUDA toolkits side by side. PyTorch, JAX and TF
each prefer a specific version range, so being able to switch is a routine
need rather than an emergency.

## Installing additional toolkits
```bash
sudo apt install cuda-toolkit-12-4   # installs under /usr/local/cuda-12.4
```

Anything installed from the NVIDIA developer repo lands at `/usr/local/cuda-<X.Y>`.
A symlink `/usr/local/cuda` points at the system-default one.

## Switching (per-user, recommended)
Settings → CUDA → "Use for me" writes `~/.config/aurum/cuda.env`. Login shells
source it via `/etc/profile.d/aurum-dl.sh`, which sets `CUDA_HOME`, `PATH`,
and `LD_LIBRARY_PATH` to point at the chosen toolkit.

Apply without re-logging in:
```bash
source ~/.config/aurum/cuda.env
nvcc --version
```

## Switching (system-wide)
Settings → CUDA → "Set system default" rewrites `/usr/local/cuda` via the
polkit-authorized helper `/usr/local/libexec/aurum-cuda-switch`.

System default affects the system DL venv at `/opt/aurum-dl-venv`. Per-user
overrides take precedence in interactive shells.

## Driver vs toolkit
Confusion source: `nvidia-smi` reports the **driver** version (e.g. 555),
`nvcc --version` reports the **toolkit** version (e.g. 12.4). The driver
ships with the kernel module and is updated by `apt`; the toolkit ships with
the compiler / runtime libraries the Python wheels link against. Mixing
toolkits is safe as long as the driver's CUDA major version supports the
toolkit's major version (driver 525+ → CUDA 12.x).

## Resetting
If the symlink ever ends up broken:
```bash
sudo ln -sfn /usr/local/cuda-12.6 /usr/local/cuda
```
