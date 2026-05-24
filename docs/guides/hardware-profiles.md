# Hardware Profiles

AurumOS auto-classifies your machine into one of four tiers at install time
and on every boot. The result is written to `/etc/aurum/profile.conf` and
read by every Wave 8/9 launcher (vLLM, Unsloth, ComfyUI, Continue.dev,
Langfuse, DSPy) plus the Settings → Hardware panel.

## The four tiers

| Tier          | VRAM           | RAM        | Example hardware                |
|---------------|----------------|------------|---------------------------------|
| `lite`        | 0 (no CUDA)    | < 16 GB    | CPU-only laptop, Docker preview |
| `standard`    | 6 – 12 GB      | 16 – 32 GB | RTX 5060 / 4060 / 3060 (8 GB)   |
| `pro`         | 12 – 16 GB     | 32 – 64 GB | RTX 4070 / 4080 (12–16 GB)      |
| `workstation` | 24 GB+         | 64 GB+     | RTX 4090, A6000, dual-GPU       |

`standard` is the 80% target — when in doubt, the detection script biases
toward it.

## What each profile installs

| Setting           | lite               | standard            | pro                  | workstation              |
|-------------------|--------------------|---------------------|----------------------|--------------------------|
| Ollama default    | `qwen2.5-coder:1.5b` | `qwen2.5-coder:7b` | `qwen2.5-coder:14b`  | `qwen2.5-coder:32b`      |
| Ollama chat       | `qwen2.5:1.5b`     | `qwen2.5:7b`        | `qwen2.5:14b`        | `qwen2.5:32b`            |
| ComfyUI flags     | `--cpu`            | `--medvram`         | `--highvram`         | `--highvram --bf16-vae`  |
| vLLM args         | `--device cpu`     | awq, 8 k context    | awq, 16 k context    | fp16, 32 k context       |
| Unsloth recipe    | `qlora-4bit-1b`    | `qlora-4bit-7b`     | `qlora-4bit-14b`     | `qlora-4bit-32b`         |
| SD model          | `sd15-int8`        | `sdxl-turbo-int8`   | `sdxl-fp16`          | `sdxl-fp16`              |
| Whisper           | `tiny`             | `small`             | `medium`             | `large-v3`               |
| YOLO              | `yolov11n`         | `yolov11s`          | `yolov11m`           | `yolov11x`               |
| SAM               | `sam2-tiny`        | `sam2-base`         | `sam2-large`         | `sam2-large`             |
| LLaVA             | `llava-phi-int4`   | `llava-7b-int4`     | `llava-13b-int4`     | `llava-34b-int4`         |

## Inspecting the active profile

```bash
# Dump the resolved values without writing to /etc:
bash /usr/local/bin/aurum-detect-profile --print

# Or just read the live conf:
cat /etc/aurum/profile.conf
```

Open **Settings → Hardware** for the same values with a coloured tier badge
and an override row.

## Overriding the tier

Two ways, both discouraged:

1. **Persistent**: drop `AURUM_PROFILE=pro` into `/etc/environment` (or a
   file under `/etc/profile.d/`) before boot. The detect script honors the
   env var as a hard override.
2. **One-shot regenerate**:
   ```bash
   sudo AURUM_PROFILE=pro /usr/local/bin/aurum-detect-profile
   ```

> Forcing a profile higher than your hardware causes OOM crashes on the
> first model load. Forcing a profile lower wastes capacity. The auto-
> detection is conservative — trust it.

## How detection works

The script (`distro/post-install/00-detect-profile.sh`):

1. **VRAM** — `nvidia-smi --query-gpu=memory.total --format=csv,noheader,nounits`
   (first GPU). Missing/empty/non-numeric → 0.
2. **RAM** — `awk '/^MemTotal:/ {print int($2/1024/1024)}' /proc/meminfo`.
3. **GPU name** — `nvidia-smi --query-gpu=name --format=csv,noheader`.
4. **CUDA available** — `nvidia-smi` on PATH AND VRAM > 0.
5. **Tier**: applies the table above against (VRAM, RAM). `$AURUM_PROFILE`
   short-circuits classification.

## C++ / QML access

```cpp
#include <aurum/profile_client.h>
auto& p = aurum::ProfileClient::instance();
QString tier = p.profile();           // "standard"
int vram = p.vramMb();
QString ollama = p.get("AURUM_OLLAMA_DEFAULT");
```

```qml
import Aurum.Aqua 1.0
Text { text: "Tier: " + profileClient.profile }
```

The QML side reaches the singleton through the `profileClient` context
property registered by `aurum-settings/main.cpp`. Other Aurum apps can do
the same (see `desktop/settings/main.cpp` for the one-liner).

## Re-detect on hardware changes

Detection runs on every boot via `aurum-detect-profile.service`. If you
hot-plug an eGPU mid-session, either reboot or:

```bash
sudo systemctl start aurum-detect-profile.service
# then in any running Aurum Qt app, the next ProfileClient::reload() picks
# up the new values (Settings → Hardware exposes a "Re-detect" button).
```
