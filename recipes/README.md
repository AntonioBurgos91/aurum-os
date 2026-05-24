# AurumOS recipes

Ready-to-run scripts for quantization and fine-tuning. The `aurum-finetune`
CLI (`tools/aurum-finetune`) picks the right fine-tuning recipe for the
machine's hardware profile (`/etc/aurum/profile.conf`) automatically; the
quantization recipes are invoked directly.

## Fine-tuning (QLoRA)

| Recipe                                  | VRAM    | Base model                  | LoRA rank | Notes |
|-----------------------------------------|---------|-----------------------------|-----------|-------|
| `unsloth/qlora_7b_standard.py`          | >=8 GB  | Qwen2.5-7B-Instruct (4-bit) | 16        | "standard" profile default. RTX 3060 / 4060 / 5060. |
| `unsloth/qlora_13b_pro.py`              | >=12 GB | Llama-3.1-8B-Instruct (4-bit) | 32      | "pro" profile default. RTX 4070 / 4080 / 3090. |
| `unsloth/qlora_70b_workstation.py`      | >=24 GB | Llama-3.1-70B-Instruct (4-bit) | 64     | "workstation" profile. RTX 4090 / 5090 / A6000 / H100. |
| `axolotl/configs/llama3_8b_lora.yml`    | >=14 GB | Llama-3.1-8B-Instruct       | 32        | Axolotl YAML — multi-GPU friendly; uncomment DeepSpeed block for ZeRO-2. |

All recipes:

* Use `bitsandbytes` 4-bit NF4 quantization for the base model.
* Use `adamw_8bit` (bnb) for the optimizer — cuts optimizer-state memory in half.
* Read `AURUM_FT_DATASET`, `AURUM_FT_OUT`, `AURUM_FT_MODEL` env vars so you can
  point at your own corpus / output dir / base model without editing the file.

Override the dataset:

```bash
AURUM_FT_DATASET=mlabonne/orpo-dpo-mix-40k aurum-finetune
```

## Quantization

| Recipe                                  | Input               | Output             |
|-----------------------------------------|---------------------|--------------------|
| `quantization/awq_quantize.py`          | HF fp16 model       | AWQ 4-bit dir      |
| `quantization/gptq_quantize.py`         | HF fp16 model       | GPTQ 2/3/4/8-bit   |

Both produce directories that `transformers.AutoModelForCausalLM.from_pretrained`
can load directly (AWQ via the `awq` backend, GPTQ via `optimum`).

Examples:

```bash
# AWQ 4-bit, default 128-sample pile-val calibration
python recipes/quantization/awq_quantize.py \
    --model meta-llama/Meta-Llama-3.1-8B-Instruct \
    --out  ~/models/Llama-3.1-8B-AWQ

# GPTQ 4-bit, larger calibration, domain-specific dataset
python recipes/quantization/gptq_quantize.py \
    --model mistralai/Mistral-7B-Instruct-v0.3 \
    --out  ~/models/Mistral-7B-GPTQ \
    --calib-dataset wikitext --calib-subset wikitext-103-v1 \
    --calib-samples 256
```

## Hardware tiers

`/etc/aurum/profile.conf` (set by Agent G during first-boot detection) selects:

| `AURUM_PROFILE` | RAM         | VRAM     | What `aurum-finetune` does |
|-----------------|-------------|----------|----------------------------|
| `lite`          | <16 GB      | none / iGPU | Prints "no local fine-tuning available; use peft+API" and exits 0. |
| `standard`      | 16-32 GB    | 8 GB     | `qlora_7b_standard.py` |
| `pro`           | 32-64 GB    | 12-16 GB | `qlora_13b_pro.py` |
| `workstation`   | 64+ GB      | 24+ GB   | `qlora_70b_workstation.py` |
