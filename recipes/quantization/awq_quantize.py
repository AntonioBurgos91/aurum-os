#!/usr/bin/env python3
"""AWQ quantization driver — turn an HF model into a 4-bit AWQ checkpoint.

Usage:
    python recipes/quantization/awq_quantize.py \
        --model meta-llama/Meta-Llama-3.1-8B-Instruct \
        --out  ~/models/Llama-3.1-8B-AWQ \
        [--bits 4] [--group-size 128] [--calib-samples 128]

Calibration data: by default a slice of `mit-han-lab/pile-val-backup`, the
canonical pile-validation subset the AWQ paper benchmarks on. Override with
--calib-dataset to use your own (must yield a `text` column).

The resulting directory is drop-in loadable with:
    from transformers import AutoModelForCausalLM
    m = AutoModelForCausalLM.from_pretrained("~/models/Llama-3.1-8B-AWQ",
                                             device_map="auto")
"""
from __future__ import annotations

import argparse
from pathlib import Path

from awq import AutoAWQForCausalLM
from transformers import AutoTokenizer


def parse_args() -> argparse.Namespace:
    p = argparse.ArgumentParser(description="AWQ-quantize an HF model")
    p.add_argument("--model", required=True, help="HF repo id or local path")
    p.add_argument("--out", required=True, help="output directory")
    p.add_argument("--bits", type=int, default=4, choices=[4])
    p.add_argument("--group-size", type=int, default=128)
    p.add_argument("--zero-point", action="store_true", default=True)
    p.add_argument("--version", default="GEMM", choices=["GEMM", "GEMV", "Marlin"])
    p.add_argument("--calib-dataset", default="mit-han-lab/pile-val-backup")
    p.add_argument("--calib-samples", type=int, default=128)
    return p.parse_args()


def main() -> None:
    args = parse_args()
    out = Path(args.out).expanduser()
    out.mkdir(parents=True, exist_ok=True)

    print(f"[awq] loading {args.model} (this loads in fp16, then quantizes)")
    model = AutoAWQForCausalLM.from_pretrained(
        args.model,
        safetensors=True,
        device_map="auto",
    )
    tokenizer = AutoTokenizer.from_pretrained(args.model, trust_remote_code=True)

    quant_config = {
        "zero_point": args.zero_point,
        "q_group_size": args.group_size,
        "w_bit": args.bits,
        "version": args.version,
    }

    print(f"[awq] quantizing: {quant_config}")
    model.quantize(
        tokenizer,
        quant_config=quant_config,
        calib_data=args.calib_dataset,
        max_calib_samples=args.calib_samples,
    )

    print(f"[awq] saving to {out}")
    model.save_quantized(str(out))
    tokenizer.save_pretrained(str(out))
    print(f"[awq] ok — load with AutoModelForCausalLM.from_pretrained('{out}')")


if __name__ == "__main__":
    main()
