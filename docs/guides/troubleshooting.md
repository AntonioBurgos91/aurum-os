# Troubleshooting

## "CUDA not available" from PyTorch
1. `nvidia-smi` — does it list the GPU? If not, the kernel module didn't
   load. `sudo modprobe nvidia` and check `dmesg | grep -i nvidia`.
2. `nvcc --version` — does it find a toolkit? If `command not found`, the
   `/usr/local/cuda` symlink is stale; see [CUDA management](cuda-management.md).
3. PyTorch wheel vs CUDA mismatch: PyTorch 2.5 currently expects CUDA 12.4
   runtime libs. Switching to a 13.x toolkit will break it.

## Boot takes way more than 3 seconds
```
systemd-analyze blame | head -20
```
Look for units AurumOS doesn't normally run (NetworkManager-wait-online is a
classic offender). Mask if you don't need them.

## Idle RAM is over 600 MB
```
tests/idle_bench.sh
```
shows per-process RSS. If `aurum-spotlight-indexer` is large it's mid-crawl —
that's transient, give it 60s. If `Hyprland` itself is large, check that blur
is off (`hyprctl getoption decoration:blur:enabled`).

## Bluetooth doesn't work
Phase 6 masks bluetooth at install time (ADR-0006). Re-enable:
```bash
sudo systemctl unmask bluetooth.service
sudo systemctl enable --now bluetooth.service
```

## Spotlight gives no file results
The indexer caches at `~/.cache/aurum/spotlight/index/`. Force a fresh crawl:
```bash
busctl --user call org.aurumos.SpotlightIndexerService \
    /org/aurumos/SpotlightIndexer \
    org.aurumos.SpotlightIndexer reindex
```

## GPU widget shows "—" in dock and menubar
The gpu-monitor user service hasn't started. Verify:
```bash
systemctl --user status aurum-gpu-monitor.service
```
On non-NVIDIA hardware it runs in simulation mode by design.

## MLflow tracker shows stale errors
Re-trigger the poll cycle:
```bash
busctl --user call org.aurumos.MlJobsTrackerService \
    /org/aurumos/MlJobsTracker \
    org.aurumos.MlJobsTracker poke
```

## Installer fails at "FORMATTING"
distinst rejects partitions it can't grow to fill the disk. Use the
"Rescan" button after disconnecting USB drives, then re-pick the target.
For full distinst diagnostics see `/tmp/distinst.log` from the live session.

## TensorFlow crashes with `X509_V_FLAG_NOTIFY_POLICY`
Upstream wheel skew: the `tensorflow` wheel pins a version range of
`cryptography` that binds against an older OpenSSL 1.1 symbol set, but
Pop!_OS 24.04 ships OpenSSL 3.x. Workaround:

```bash
/opt/aurum-dl-venv/bin/python -m pip install --upgrade cryptography
```

This pulls the latest `cryptography` wheel (built against OpenSSL 3) and
TensorFlow imports cleanly afterward. `aurum-dl-verify` reports the
condition without aborting the rest of the smoke run.

## `aurum-dl-verify` slow on first run / re-installs wheels every time
`02-install-dl-stack.sh` defaults to `UV_NO_CACHE=1` to keep the ISO
image lean. For repeated CI runs export `UV_NO_CACHE=0` AND set
`UV_CACHE_DIR=/path/to/persistent/cache` (a docker named volume works
well — see `.github/workflows/release.yml` for the canonical setup).
