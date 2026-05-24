# Bare-metal install guide

This guide walks you through installing AurumOS on a physical workstation.
The end result is a macOS-Sequoia-style Linux desktop sitting on a tuned
Pop!_OS 24.04 LTS base, with NVIDIA drivers verified against your GPU and a
deep-learning toolchain pre-installed: JupyterLab, Marimo, Ollama, MLflow,
PyTorch, JAX and TensorFlow. After ~25 minutes of installer time you'll
have a workstation that boots straight into the AurumOS desktop and can run
`torch.cuda.is_available() == True` in a fresh notebook.

If you only want to try the look-and-feel, see the live-ISO option in the
installer (Step 4) — you can run AurumOS from the USB without touching the
internal disk.

---

## System requirements

| Category | Minimum                            | Recommended                                |
|----------|------------------------------------|--------------------------------------------|
| CPU      | x86_64, 4 cores                    | 8+ cores (AVX2 required for some wheels)   |
| RAM      | 16 GB                              | 32–64 GB                                   |
| Disk     | 80 GB SSD                          | 500 GB NVMe (models + datasets get fat)    |
| GPU      | Optional (CPU fallback works)      | NVIDIA RTX 3060 / A4000 / H100             |
| Display  | 1280×800                           | 1920×1200 or higher                        |
| Network  | required for ISO download          | gigabit recommended for first-boot setup   |

ARM (aarch64) is **not** supported in v0.1. AMD GPUs work for desktop
rendering but the ML stack assumes CUDA — use Pop!_OS classic if you need
ROCm.

---

## Pre-install checklist

Before you boot the installer:

- [ ] **Secure Boot disabled** in BIOS/UEFI. The proprietary NVIDIA kernel
      module is not signed, so Secure Boot will refuse to load it. (You can
      re-enable Secure Boot later by enrolling your own MOK key — see
      [`troubleshooting.md`](troubleshooting.md).)
- [ ] **TPM** can stay on or off; AurumOS doesn't require it. If you plan to
      use disk encryption (LUKS) and want TPM-bound unlock, leave it on.
- [ ] **Backup any data on the target disk.** The guided installer wipes the
      whole disk by default.
- [ ] **Know your GPU.** Run `lspci | grep -i nvidia` on your current OS,
      or check the sticker on the card. Cross-reference with
      [`nvidia-driver-matrix.md`](nvidia-driver-matrix.md) to know which
      driver version you'll want.
- [ ] **Have an Ethernet cable handy.** The installer can do Wi-Fi but
      driver downloads are noticeably faster on wired.
- [ ] **An 8 GB or larger USB stick.** Anything you keep on it will be lost.

---

## Step 1 — Download the ISO

Grab the latest release ISO from the AurumOS site:

```
https://aurumos.dev/download/v0.1.0-beta/aurumos-v0.1.0-beta.iso
```

> **Note:** the URL above is a placeholder — release hosting is being
> finalised. Update this guide once the release page is live, or grab the
> nightly artefact from the GitHub Actions release pipeline.

The download is ~3.4 GB. Once it lands, verify the SHA-256:

```bash
# On Linux/macOS
sha256sum aurumos-v0.1.0-beta.iso
# or:
shasum -a 256 aurumos-v0.1.0-beta.iso
```

Compare the output against `aurumos-v0.1.0-beta.iso.sha256` published
alongside the ISO. If the hashes don't match, **stop** and re-download —
do not flash a corrupted image.

---

## Step 2 — Create a bootable USB

Plug in your USB stick. Choose the recipe for the OS you're flashing from.

### From Linux

Find the device node. **Be sure** — picking the wrong `/dev/sdX` will
overwrite your system disk.

```bash
lsblk
# e.g. /dev/sdb  14.5G  USB Flash Drive
```

Then flash:

```bash
sudo dd if=aurumos-v0.1.0-beta.iso of=/dev/sdX bs=4M status=progress conv=fsync
sync
```

Replace `/dev/sdX` with your USB device (not a partition like `/dev/sdX1`).

### From macOS

```bash
diskutil list
# Identify the USB, e.g. /dev/disk4

diskutil unmountDisk /dev/disk4
sudo dd if=aurumos-v0.1.0-beta.iso of=/dev/rdisk4 bs=4m status=progress
sync
diskutil eject /dev/disk4
```

Use the `rdisk` variant — it's an order of magnitude faster than `disk`.

### From Windows

Use **Rufus** (recommended) or **balenaEtcher**. In Rufus:

1. Device: select the USB.
2. Boot selection: choose the AurumOS ISO.
3. Partition scheme: **GPT**.
4. Target system: **UEFI (non CSM)**.
5. When prompted, choose **Write in DD image mode** (not ISO mode).

balenaEtcher does the right thing automatically — just point it at the
ISO and the target USB.

### Verify the USB

After flashing, plug the USB into another machine to confirm it's bootable,
or run `lsblk -f /dev/sdX` (Linux) and check that you see an `iso9660`
volume labelled `AURUMOS_LIVE`.

---

## Step 3 — Boot the installer

1. Insert the USB and reboot the target machine.
2. Mash the boot-menu key during POST:
   - Dell / Lenovo desktops: **F12**
   - HP / ASUS: **F9** or **Esc → F9**
   - MSI / Gigabyte / most workstation boards: **F11**
   - Framework / System76: **F7**
   - Generic UEFI: **F2** or **Del** to enter setup, then change boot order
3. Pick the USB entry. UEFI-mode is preferred — most menus prefix it with
   `UEFI:`.
4. The GRUB menu shows three options. Default to **Try or Install
   AurumOS**. Wait ~30 seconds for the live environment to come up — you'll
   see the Hyprland splash, then the desktop.

If the screen stays black after the splash, see Common issues at the end —
this is nearly always a Secure Boot or NVIDIA-driver issue.

---

## Step 4 — Run the AurumOS installer

Double-click **Install AurumOS** on the live desktop, or pick it from the
dock. The wizard (`aurum-installer`) walks you through:

1. **Welcome** — pick a language. Defaults to system locale of the live
   environment.
2. **Locale** — keyboard layout and timezone.
3. **Account** — username, password, hostname. Auto-login is offered and
   defaults to **off** for workstations.
4. **Disk** — partitioning, the only step with real consequences (see below).
5. **NVIDIA driver** — the installer probes `lspci` and pre-selects a
   recommended driver from the
   [compatibility matrix](nvidia-driver-matrix.md). Override only if you
   know you need something specific.
6. **Summary** — last chance to cancel.
7. **Install** — ~12–20 minutes depending on disk speed.
8. **Done** — eject the USB and reboot.

### Partitioning modes

- **Guided — erase whole disk** (default): wipes the chosen disk, creates a
  500 MB EFI partition, a small swap, and ext4 for the rest. Pick this for
  a dedicated workstation.
- **Guided — encrypt whole disk**: same as above but the root partition
  uses LUKS2. You'll be asked for a passphrase.
- **Manual**: opens GParted. Use this for dual-boot or custom layouts.

### Dual-boot with Windows

The installer **does not** resize an existing Windows partition. Do the
shrink from Windows first:

1. Boot into Windows.
2. Open **Disk Management** (`diskmgmt.msc`).
3. Right-click the C: partition → **Shrink Volume** → free up at least
   80 GB.
4. Boot the AurumOS USB.
5. In the installer, choose **Manual** partitioning. Create:
   - ext4 mounted at `/` in the freed space.
   - Keep the existing EFI System Partition; mount it at `/boot/efi` and
     **do not** tick "format".
6. Finish the install. GRUB will detect Windows on the next boot.

### NVIDIA driver step

The installer caches the three driver families it needs (legacy 470,
stable 535, latest 550) on the ISO, so this step is offline. Defaults to
**550.x** as of v0.1.0-beta. If your card is in the **Pascal** family or
older, accept the suggested fallback to 535 — you can switch later with
`aurum-cuda-switch`.

---

## Step 5 — First boot

1. Pull the USB. Reboot. GRUB shows AurumOS as the default; press Enter or
   wait 5 seconds.
2. The Plymouth splash runs for ~20 seconds while `aurum-launcher` brings
   up the D-Bus session, three Rust daemons, Hyprland and finally the
   desktop shell.
3. You land on the desktop: menubar at the top, dock at the bottom, a
   single wallpaper, no windows.
4. **First-run setup** opens automatically:
   - Connect to Wi-Fi (skip if you used Ethernet).
   - Choose optional Ollama models to pre-pull (Llama-3-8B, Phi-3-mini,
     Qwen2.5-coder-7B). Each adds 2–8 GB to the disk footprint.
   - Choose which JupyterLab kernels to register (PyTorch, JAX, TF,
     Pyodide). All three CUDA kernels need the GPU driver to be loaded —
     if your card is unsupported, skip them now and add them later.
   - Click **Finish**. The setup runs in the background; the desktop is
     usable while it works.

---

## Step 6 — Verify the deep-learning stack

Open the dock's terminal (or press **Cmd+Space → "terminal"** in
Spotlight) and run the smoke test:

```bash
python3 /usr/share/aurum-os/tests/dl_smoke.py
```

Expected output (one line per framework):

```
[PASS] torch              2.4.0+cu123   cuda=True   devices=1
[PASS] jax                0.4.30        cuda=True   devices=1
[PASS] tensorflow         2.17.0        cuda=True   devices=1
[PASS] transformers       4.44.0
[PASS] mlflow             2.15.1        server=http://localhost:5000
```

`[SKIP]` is fine — it means the framework wasn't selected in first-run.
`[FAIL]` for `cuda=False` when you expected GPU means the driver isn't
loaded; see **GPU not detected** below.

For a deeper sanity check, click **JupyterLab** in the dock, open a new
notebook and run:

```python
import torch
print(torch.cuda.is_available())          # True
print(torch.cuda.get_device_name(0))      # e.g. NVIDIA RTX 4090
print(torch.randn(1024, 1024, device="cuda") @ torch.randn(1024, 1024, device="cuda"))
```

If that runs without error and finishes in under a second, you're in
business.

---

## Common issues

### No screen after boot

Drop to a TTY with **Ctrl+Alt+F3**, log in, then check the launcher
journal:

```bash
journalctl -u aurum-desktop --since "5 min ago" -n 200
```

The two most common causes:

1. **Wrong NVIDIA driver.** Look for `NVRM: API mismatch` or
   `nvidia-modeset: not loaded` in `dmesg`. Switch to a different driver:

   ```bash
   aurum-cuda-switch --driver 535
   sudo reboot
   ```

   See [`nvidia-driver-matrix.md`](nvidia-driver-matrix.md) for which
   driver version your card wants.

2. **Secure Boot re-enabled.** Boot into BIOS, disable Secure Boot,
   reboot.

### GPU not detected

From any terminal:

```bash
nvidia-smi
```

If the output is empty or `command not found`:

```bash
lsmod | grep nvidia
# Should list nvidia, nvidia_modeset, nvidia_uvm, nvidia_drm

dkms status
# Should show nvidia/<version>, installed for your running kernel
```

If `dkms status` shows the module built but `lsmod` doesn't list it, the
kernel rejected loading it — usually Secure Boot or a kernel-driver ABI
mismatch after a kernel update. Re-build:

```bash
sudo dkms autoinstall
sudo reboot
```

### Wayland artifacts (flicker, tearing)

Try the Vulkan renderer:

```bash
sudo sed -i 's/^# *WLR_RENDERER=.*/WLR_RENDERER=vulkan/' /etc/aurum/hypr/aurum.conf
# Log out and back in.
```

If that makes it worse, fall back to GLES2 by setting `WLR_RENDERER=gles2`.

### Dock empty

If the dock comes up with no icons:

```bash
ls ~/.config/aurum/dock.list
# No such file? Recreate defaults:
aurum-install-assets --component dock
```

Then restart the dock: **Cmd+Space → "Restart Dock"**.

### Spotlight returns no results

The Tantivy index hasn't built yet. Force a rebuild:

```bash
systemctl --user restart aurum-spotlight-indexer
journalctl --user -u aurum-spotlight-indexer -f
# Wait for "index ready: N documents"
```

### Installer crashes on partitioning

Almost always a flaky USB. Re-flash the ISO with `conv=fsync` (Linux) or
let Etcher validate after write. If it persists, swap the USB stick — some
budget flash drives drop writes silently.

---

## Uninstall / reinstall

AurumOS shares Pop!_OS's recovery partition layout. You have three
options:

1. **Reset from recovery.** Reboot, hold **Space** at GRUB, select
   `Pop!_OS Recovery`. Choose **Refresh OS** to keep your home, or
   **Reinstall OS** to wipe.
2. **Reinstall over the top.** Boot the AurumOS USB again, run the
   installer, choose **Manual** and reuse the existing `/` partition
   without formatting `/home`. Your data survives; system files are
   replaced.
3. **Wipe and start fresh.** Boot any Linux installer USB and let it
   reformat the disk. Nothing about AurumOS is special at the disk level.

---

## Next steps

- [`dl-quickstart.md`](dl-quickstart.md) — set up your first project and
  MLflow experiment.
- [`cuda-management.md`](cuda-management.md) — pinning per-project CUDA
  toolkit versions.
- [`spotlight-plugins.md`](spotlight-plugins.md) — extending the launcher.
- [`troubleshooting.md`](troubleshooting.md) — everything that goes wrong
  past first boot.
