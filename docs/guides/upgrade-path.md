# Upgrade path — moving up the profile ladder

`/etc/aurum/profile.conf` is regenerated on every boot by
`aurum-detect-profile.service`, so most of the time you don't have to do
anything when your hardware changes — reboot and everything reconfigures
itself.

The exceptions are weights (which were sized for your old tier) and
user-level configs (`~/.continue/config.json`, `~/.config/aider/`) which
the system can't safely overwrite without your consent.

This guide is the 60-second recipe for the most common upgrade story.

## I just installed an RTX 5060 (was CPU-only). What do I do?

```bash
# 1. Reboot so the NVIDIA driver loads and nvidia-smi works.
sudo systemctl reboot

# 2. Confirm the new tier was detected.
aurum-detect-profile --print | grep AURUM_PROFILE
#   → AURUM_PROFILE=standard

# 3. (One-shot — the service already did this on boot, but no-op-safe.)
sudo aurum-detect-profile

# 4. Rewrite Continue.dev to point at the bigger coder model.
aurum-configure-continue

# 5. Pull the standard-tier model packs.
aurum-model-pack install coding    # qwen2.5-coder:7b + nomic-embed-text
aurum-model-pack install vision    # YOLOv11s + SAM 2 base + DINOv2 + CLIP
aurum-model-pack install imagegen  # SDXL Turbo into ComfyUI

# 6. Open Aurum Settings → Hardware to verify the tier badge says "standard".
xdg-open 'aurum-settings://hardware'
```

That's it. New defaults will be picked up automatically by:

* **Ollama** — `aurum-detect-profile` rewrites the default model env vars;
  Open WebUI on `:8080` switches to `qwen2.5:7b`.
* **vLLM** — `aurum-vllm-serve` now passes `--quantization awq`.
* **ComfyUI** — `aurum-launch-comfyui` now passes `--medvram`.
* **Continue.dev** — after `aurum-configure-continue`, the
  `provider.model` becomes `qwen2.5-coder:7b`.
* **Settings → Hardware** — the panel re-reads `/etc/aurum/profile.conf`
  and updates its badge + table.

## I just upgraded from 5060 to 4070 (standard → pro)

```bash
sudo systemctl reboot
aurum-detect-profile --print | grep AURUM_PROFILE   # → pro
sudo aurum-detect-profile
aurum-configure-continue
aurum-model-pack install coding     # idempotent; pulls 14B variant now
aurum-model-pack upgrade            # convenience: re-pulls all installed packs at the new tier
```

Extra steps that apply at `pro`:

* `axolotl` and `deepspeed` are now usable for full fine-tuning runs.
* `recipes/unsloth/qlora_13b_pro.py` becomes the default Unsloth recipe.
* vLLM gains `--speculative-decoding` flags.

## I just installed a second 4090 (pro → workstation)

```bash
sudo systemctl reboot
aurum-detect-profile --print | grep AURUM_PROFILE   # → workstation
sudo aurum-detect-profile
aurum-configure-continue
aurum-model-pack install workstation   # llama3.3:70b-q4, deepseek-r1 distill, SD 3.5 large
aurum-model-pack upgrade               # re-pulls coding pack at qwen2.5-coder:32b
```

Extra steps that apply at `workstation`:

* vLLM `--tensor-parallel-size 2` becomes the default.
* `recipes/unsloth/qlora_70b_workstation.py` is the new default Unsloth
  recipe.
* ComfyUI gains `--bf16-vae` for SD3 / Flux.

## I'm downgrading (laptop dies, falling back to a CPU box)

Same recipe in reverse — the system will *function* immediately after a
reboot (everything falls back to `lite`), but you'll be sitting on
gigabytes of weights you can't run:

```bash
# Free disk space — purges weights gated above the new tier.
aurum-model-pack prune
# (Use aurum-model-pack list --installed to inspect first.)
```

## What does `aurum-configure-continue` actually do?

It rewrites `~/.continue/config.json` to use the model named in
`/etc/aurum/profile.conf:AURUM_OLLAMA_DEFAULT`. The file is a JSON list
of provider configurations; the tool patches the entry whose
`provider == "ollama"` and `title.startswith("AurumOS")` and leaves
every other entry (your custom OpenAI key, your Anthropic key, etc.)
untouched.

If you have heavily customised your Continue config you can opt out by
deleting the AurumOS-marked entry; the tool will then leave you alone.

## What does `aurum-model-pack upgrade` do?

It walks the list of *currently installed* packs and re-runs `install`
for each one. Because the pack YAMLs carry per-model `min_profile`
gates, models that need a bigger GPU than you used to have are now
fetched, while models you already have are no-ops (Ollama dedupes by
digest; HuggingFace dedupes by checksum).

It does **not** delete the smaller variant — that's `prune`'s job.

## Troubleshooting

* **Profile still says `lite` after reboot** — check
  `journalctl -u aurum-detect-profile`. The usual cause is the NVIDIA
  driver not having loaded by the time the service fired; running
  `sudo aurum-detect-profile` manually resolves it.
* **Continue.dev still using the old model** — re-run
  `aurum-configure-continue`, then *Reload Window* in VSCode. Continue
  caches the config in memory.
* **`aurum-model-pack install` says "no GPU"** — the pack honours its
  `min_profile`. If the new card was missed by detection, set
  `AURUM_PROFILE=pro` in `/etc/environment` and re-run.
* **Disk filled up mid-upgrade** — `aurum-model-pack` writes to
  `~/.cache/aurum/models/` and `/opt/aurum-comfyui/models/` by default.
  Symlink either to a larger volume before `install`.

## See also

* [hardware-profiles.md](./hardware-profiles.md) — what the tiers
  actually mean and how detection works.
* [sota-2026-stack.md](./sota-2026-stack.md) — full matrix of what
  changes between tiers.
