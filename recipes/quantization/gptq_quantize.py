#!/usr/bin/env python3
"""GPTQ quantization driver via AutoGPTQ.

Usage:
    python recipes/quantization/gptq_quantize.py \
        --model meta-llama/Meta-Llama-3.1-8B-Instruct \
        --out  ~/models/Llama-3.1-8B-GPTQ \
        [--bits 4] [--group-size 128] [--calib-samples 128]

Calibration: 128 samples from `c4` (subset `en`, split `validation`) by
default. GPTQ is more sensitive to calibration set choice than AWQ; for
domain-specific quantization use --calib-dataset / --calib-column to feed
your own corpus.

Output is drop-in loadable with transformers' AutoModelForCausalLM (optimum
handles the GPTQ kernel wiring).
"""
from __future__ import annotations

import argparse
import random
from pathlib import Path

import torch
from auto_gptq import AutoGPTQForCausalLM, BaseQuantizeConfig
from datasets import load_dataset
from transformers import AutoTokenizer


def parse_args() -> argparse.Namespace:
    p = argparse.ArgumentParser(description="GPTQ-quantize an HF model")
    p.add_argument("--model", required=True, help="HF repo id or local path")
    p.add_argument("--out", required=True, help="output directory")
    p.add_argument("--bits", type=int, default=4, choices=[2, 3, 4, 8])
    p.add_argument("--group-size", type=int, default=128)
    p.add_argument("--desc-act", action="store_true",
                   help="enable activation-order (slower, slightly better PPL)")
    p.add_argument("--calib-dataset", default="allenai/c4")
    p.add_argument("--calib-subset", default="en")
    p.add_argument("--calib-split", default="validation")
    p.add_argument("--calib-column", default="text")
    p.add_argument("--calib-samples", type=int, default=128)
    p.add_argument("--seq-len", type=int, default=2048)
    p.add_argument("--seed", type=int, default=42)
    return p.parse_args()


def build_calib_dataset(tokenizer, args) -> list[dict]:
    """Pull args.calib_samples random rows; tokenize to args.seq_len."""
    random.seed(args.seed)
    ds = load_dataset(
        args.calib_dataset,
        args.calib_subset,
        split=args.calib_split,
        streaming=True,
    )
    samples: list[dict] = []
    for row in ds:
        text = row.get(args.calib_column, "")
        if not text or len(text) < 200:
            continue
        enc = tokenizer(text, return_tensors="pt",
                        truncation=True, max_length=args.seq_len)
        if enc.input_ids.shape[1] < args.seq_len // 2:
            continue
        samples.append({"input_ids": enc.input_ids, "attention_mask": enc.attention_mask})
        if len(samples) >= args.calib_samples:
            break
    if not samples:
        raise RuntimeError("no calibration samples collected — check --calib-* flags")
    return samples


def main() -> None:
    args = parse_args()
    out = Path(args.out).expanduser()
    out.mkdir(parents=True, exist_ok=True)

    tokenizer = AutoTokenizer.from_pretrained(args.model, trust_remote_code=True)

    quant_config = BaseQuantizeConfig(
        bits=args.bits,
        group_size=args.group_size,
        desc_act=args.desc_act,
        damp_percent=0.01,
    )

    print(f"[gptq] loading {args.model} in fp16")
    model = AutoGPTQForCausalLM.from_pretrained(
        args.model,
        quantize_config=quant_config,
        torch_dtype=torch.float16,
    )

    print(f"[gptq] preparing {args.calib_samples} calibration samples")
    calib = build_calib_dataset(tokenizer, args)

    print(f"[gptq] quantizing bits={args.bits} group_size={args.group_size}")
    model.quantize(calib)

    print(f"[gptq] saving to {out}")
    model.save_quantized(str(out), use_safetensors=True)
    tokenizer.save_pretrained(str(out))
    print(f"[gptq] ok — load with AutoModelForCausalLM.from_pretrained('{out}')")


if __name__ == "__main__":
    main()
