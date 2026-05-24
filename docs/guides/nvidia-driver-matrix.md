# NVIDIA driver compatibility matrix

This page lists the NVIDIA driver and CUDA toolkit versions AurumOS ships
for each GPU family, plus how the installer picks one and how to switch
afterwards. If you only want a quick answer for a new card, scan the
table.

For day-to-day toolkit switching (`nvcc`, `LD_LIBRARY_PATH`,
per-project pinning), see [`cuda-management.md`](cuda-management.md) — this
page covers the *driver*, the kernel module that talks to the card.

---

## Matrix

| GPU family           | Examples                                | Min driver  | Recommended driver | CUDA version | Notes                                                                 |
|----------------------|-----------------------------------------|-------------|--------------------|--------------|-----------------------------------------------------------------------|
| Hopper               | H100, H200                              | 535.86.10   | 550.54.15          | 12.3+        | Requires Linux 6.1+ kernel; AurumOS 0.1 ships 6.8.                    |
| Ada Lovelace         | RTX 4090 / 4080 / 4070, L4, L40         | 525.60.13   | 550.54.15          | 12.0+        | Use 550+ for FP8 (Transformer Engine) workloads.                      |
| Ampere               | RTX 3090 / 3080, A100, A40, A5000       | 470.42.01   | 550.54.15          | 11.4+        | 470 works but caps you at CUDA 11.4 — upgrade for modern wheels.      |
| Turing               | RTX 2080 / 2070, T4, Quadro RTX 4000+   | 440.33.01   | 535.183.01         | 11.0+        | Driver 550 also works but offers no functional advantage.             |
| Pascal               | GTX 1080 / 1070, P100, P40              | 396.26      | 535.183.01         | 10.0–11.x    | Will not get CUDA 12 — sm_60/sm_61 dropped from PTX in 12.x.          |
| Maxwell              | GTX 970 / 980, M60, M40                 | 367.18      | 470.256.02 (legacy)| 10.0–11.0    | Limited modern PyTorch wheel support; only `+cu118` and older work.   |
| Kepler / Fermi / older | GTX 700 / 600 series, Tesla K20/K40   | —           | —                  | —            | Not supported by AurumOS — use Pop!_OS classic with the legacy 470.   |

**Always check** the
[NVIDIA driver release notes](https://www.nvidia.com/Download/Find.aspx)
for new card revisions — Ada SUPER refreshes and H200 SXM5 boards have
landed in driver bumps mid-cycle.

> Versions in the table are "ships in AurumOS 0.1.0-beta". They are
> updated each release; check `apt list --installed | grep nvidia-driver`
> after install to see what you actually have.

---

## How AurumOS selects the driver

At install time, the wizard probes:

```bash
lspci -nn | grep -E "VGA|3D"
```

It parses the PCI ID (the `[vendor:device]` bit), looks it up in the
table above, and pre-selects the matching driver. You can override on the
**NVIDIA driver** wizard page — useful if you know a specific point
release fixes a bug you've hit.

For multi-GPU systems with different generations (e.g. an A100 + a 4090),
the installer picks the **lowest minimum** that covers both. In practice
that's almost always the latest stable, because all modern families
share the unified open-kernel-module path.

You can re-run the probe on an installed system:

```bash
aurum-probe-gpu
# 0000:01:00.0  NVIDIA RTX 4090     family=ada    recommended=550.54.15
# 0000:02:00.0  NVIDIA A100-SXM4    family=ampere recommended=550.54.15
```

---

## Switching drivers post-install

Use the wrapper — **do not** edit `/usr/lib/x86_64-linux-gnu/libcuda.so`
or apt-purge `nvidia-driver-*` by hand:

```bash
aurum-cuda-switch --driver 535
```

`aurum-cuda-switch` is a polkit-elevated wrapper that:

1. Verifies the requested driver is installed (or installs it via apt).
2. Stops `aurum-desktop`.
3. Unloads the running nvidia modules (forcing a reboot if the GPU is in
   use).
4. Swaps the `/usr/lib/x86_64-linux-gnu/libcuda.so` symlink to point at
   the new driver's userspace stub.
5. Updates `/etc/aurum/cuda.env` so login shells get the matching
   `CUDA_HOME`.

Running it as plain `root` skips the policy check that prevents you from
switching to a driver that doesn't support your card — there's a reason
the wrapper exists. Use it.

To list installed drivers:

```bash
aurum-cuda-switch --list
# * 550.54.15  (active)
#   535.183.01
#   470.256.02 (legacy)
```

To revert if a switch goes wrong, the previous symlink target is saved at
`/var/lib/aurum/cuda-switch/previous`. From a recovery shell:

```bash
ln -sfn $(cat /var/lib/aurum/cuda-switch/previous) /usr/lib/x86_64-linux-gnu/libcuda.so
```

---

## CUDA toolkit vs driver

A frequent source of confusion. They're two different things shipped by
NVIDIA in two different ways:

- **Driver** = kernel module (`nvidia.ko`, `nvidia_modeset.ko`,
  `nvidia_uvm.ko`) **+** the userspace shim `libcuda.so`. Talks to the
  hardware. Updated by `apt upgrade` and a reboot. Reported by
  `nvidia-smi`.
- **CUDA toolkit** = `nvcc`, headers, math libraries (`libcublas`,
  `libcurand`, `libcufft`), profilers. The thing your code links
  against. Reported by `nvcc --version`. Multiple toolkits can sit
  side-by-side under `/usr/local/cuda-X.Y`.

Compatibility rule of thumb:

> A driver supports any toolkit with the **same or lower** major version.
> Driver 550 supports CUDA 12.x and 11.x; driver 470 only supports
> CUDA 11.4 and earlier.

AurumOS ships **CUDA 12.3** as the system default, linked from
`/usr/local/cuda → /usr/local/cuda-12.3`. To install additional toolkits,
see [`cuda-management.md`](cuda-management.md#installing-additional-toolkits).

---

## Container access (Docker / Podman)

If you want containerised workloads to see the GPU, install
`nvidia-container-toolkit`:

```bash
sudo apt install nvidia-container-toolkit
sudo nvidia-ctk runtime configure --runtime=docker
sudo systemctl restart docker
```

For Podman (rootless or rootful):

```bash
sudo nvidia-ctk runtime configure --runtime=podman
# (rootless: also append "nvidia.com/gpu=all" to your CDI device list)
```

Smoke test:

```bash
docker run --rm --gpus all nvcr.io/nvidia/pytorch:24.04-py3 nvidia-smi
# Should print the same nvidia-smi output as on the host.
```

Notes:

- The toolkit version on the host must be `>=` the toolkit version baked
  into the container image. Driver mismatches the other way around
  (newer driver, older image) are fine.
- Rootless Podman needs `crun` not `runc` for CUDA device passthrough on
  cgroups v2 — both ship in AurumOS, just make sure `~/.config/containers/containers.conf`
  has `runtime = "crun"`.
- For Kubernetes (k3s, kind), use the NVIDIA device plugin DaemonSet —
  outside the scope of this doc.

---

## When the matrix lies

The recommended driver is the one we've tested against the framework
wheels we ship. If you need a specific driver because:

- You're running a CUDA preview (e.g. 12.5 nightly).
- You hit a NVIDIA-confirmed bug fixed in a point release we haven't
  picked up yet.
- You need the **open** kernel module (`nvidia-open`) for SR-IOV.

…then override on the installer page or run `aurum-cuda-switch
--driver <exact-version>` afterwards. File an issue with the driver
version, the symptom and `aurum-probe-gpu` output so we can update the
matrix.
