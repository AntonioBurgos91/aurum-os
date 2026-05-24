#!/usr/bin/env python3
"""QLoRA fine-tune of Qwen2.5-7B on 8 GB VRAM (AurumOS "standard" profile).

Target hardware: RTX 5060 / 4060 Ti / 3060 (8 GB).
Base model:      Qwen/Qwen2.5-7B-Instruct  (4-bit NF4)
LoRA rank:       16, alpha 16, dropout 0
Context:         2048 tokens (raise to 4096 if you have headroom)
Trainer:         trl.SFTTrainer via Unsloth's FastLanguageModel patches.

Run:
    aurum-finetune                          # picks this recipe on "standard"
    /opt/aurum-dl-venv/bin/python recipes/unsloth/qlora_7b_standard.py

The script is dataset-agnostic by default: it loads `tatsu-lab/alpaca` for a
quick sanity smoke. Swap `DATASET` / `format_prompt` for your own corpus.
"""
from __future__ import annotations

import os
from pathlib import Path

# Unsloth must be imported BEFORE transformers/peft to install its kernel
# patches. The import warns loudly on CUDA-less hosts; that is expected and
# does not block the recipe layout from being valid.
from unsloth import FastLanguageModel  # noqa: E402
from datasets import load_dataset
from trl import SFTTrainer, SFTConfig

MODEL_NAME = "unsloth/Qwen2.5-7B-Instruct-bnb-4bit"
MAX_SEQ_LEN = 2048
OUTPUT_DIR = Path(os.environ.get("AURUM_FT_OUT", "~/finetune-out/qwen2.5-7b-qlora")).expanduser()
DATASET = os.environ.get("AURUM_FT_DATASET", "tatsu-lab/alpaca")


def main() -> None:
    OUTPUT_DIR.mkdir(parents=True, exist_ok=True)

    model, tokenizer = FastLanguageModel.from_pretrained(
        model_name=MODEL_NAME,
        max_seq_length=MAX_SEQ_LEN,
        dtype=None,            # auto: bf16 on Ampere+, fp16 otherwise
        load_in_4bit=True,     # NF4 via bitsandbytes
    )

    # LoRA adapter — rank 16 fits comfortably on 8 GB with the 4-bit base.
    model = FastLanguageModel.get_peft_model(
        model,
        r=16,
        lora_alpha=16,
        lora_dropout=0.0,
        bias="none",
        use_gradient_checkpointing="unsloth",  # ~30% memory saving
        random_state=42,
        target_modules=[
            "q_proj", "k_proj", "v_proj", "o_proj",
            "gate_proj", "up_proj", "down_proj",
        ],
    )

    ds = load_dataset(DATASET, split="train")

    def format_prompt(row: dict) -> dict:
        # Alpaca schema — adapt for your dataset.
        instr = row.get("instruction", "")
        inp = row.get("input", "")
        out = row.get("output", "")
        prompt = (
            f"### Instruction:\n{instr}\n\n"
            + (f"### Input:\n{inp}\n\n" if inp else "")
            + f"### Response:\n{out}{tokenizer.eos_token}"
        )
        return {"text": prompt}

    ds = ds.map(format_prompt, remove_columns=ds.column_names)

    trainer = SFTTrainer(
        model=model,
        tokenizer=tokenizer,
        train_dataset=ds,
        args=SFTConfig(
            output_dir=str(OUTPUT_DIR),
            per_device_train_batch_size=2,
            gradient_accumulation_steps=8,   # effective batch 16
            warmup_steps=20,
            max_steps=200,                   # smoke run; raise for real training
            learning_rate=2e-4,
            logging_steps=10,
            optim="adamw_8bit",              # bitsandbytes 8-bit optimizer
            weight_decay=0.01,
            lr_scheduler_type="cosine",
            seed=42,
            bf16=True,
            fp16=False,
            max_seq_length=MAX_SEQ_LEN,
            dataset_text_field="text",
            report_to="none",
        ),
    )

    trainer.train()
    model.save_pretrained(str(OUTPUT_DIR / "adapter"))
    tokenizer.save_pretrained(str(OUTPUT_DIR / "adapter"))
    print(f"[ok] LoRA adapter saved to {OUTPUT_DIR / 'adapter'}")


if __name__ == "__main__":
    main()
