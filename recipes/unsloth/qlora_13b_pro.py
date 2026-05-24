#!/usr/bin/env python3
"""QLoRA fine-tune of a 13B-class model on 12-16 GB VRAM (AurumOS "pro" profile).

Target hardware: RTX 4070 Ti SUPER / 4080 / 3090 (12-16 GB).
Base model:      meta-llama/Llama-3.1-8B-Instruct (closest "13B-class" with
                 a clean 4-bit pre-quantized release; swap for Llama-2-13B if
                 you have the gated access).
LoRA rank:       32, alpha 32, dropout 0.05
Context:         4096 tokens

Compared to qlora_7b_standard.py: bigger rank, longer context, larger batch.
Still fits in 12 GB; on 16 GB you can also raise MAX_SEQ_LEN to 8192.
"""
from __future__ import annotations

import os
from pathlib import Path

from unsloth import FastLanguageModel  # noqa: E402
from datasets import load_dataset
from trl import SFTTrainer, SFTConfig

MODEL_NAME = os.environ.get(
    "AURUM_FT_MODEL",
    "unsloth/Meta-Llama-3.1-8B-Instruct-bnb-4bit",
)
MAX_SEQ_LEN = 4096
OUTPUT_DIR = Path(os.environ.get("AURUM_FT_OUT", "~/finetune-out/llama3.1-8b-qlora")).expanduser()
DATASET = os.environ.get("AURUM_FT_DATASET", "tatsu-lab/alpaca")


def main() -> None:
    OUTPUT_DIR.mkdir(parents=True, exist_ok=True)

    model, tokenizer = FastLanguageModel.from_pretrained(
        model_name=MODEL_NAME,
        max_seq_length=MAX_SEQ_LEN,
        dtype=None,
        load_in_4bit=True,
    )

    model = FastLanguageModel.get_peft_model(
        model,
        r=32,
        lora_alpha=32,
        lora_dropout=0.05,
        bias="none",
        use_gradient_checkpointing="unsloth",
        random_state=42,
        target_modules=[
            "q_proj", "k_proj", "v_proj", "o_proj",
            "gate_proj", "up_proj", "down_proj",
        ],
    )

    ds = load_dataset(DATASET, split="train")

    def format_prompt(row: dict) -> dict:
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
            per_device_train_batch_size=4,
            gradient_accumulation_steps=4,    # effective batch 16
            warmup_steps=50,
            max_steps=500,
            learning_rate=2e-4,
            logging_steps=20,
            optim="adamw_8bit",
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
