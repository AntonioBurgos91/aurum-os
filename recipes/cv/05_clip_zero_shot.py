#!/usr/bin/env python3
"""OpenCLIP zero-shot classification — AurumOS reference recipe.

Loads ViT-B-32 / laion2b weights (small, ~600 MB) and scores a sample image
against a user-supplied list of text labels. Outputs softmax probabilities.

Why ViT-B-32 as the default rather than ViT-L-14: it fits comfortably on
every AurumOS profile, runs in <1s on CPU for single-image inference, and
covers the "is the stack wired up?" use case. Production retrieval pipelines
should swap to ViT-L-14 (1.7 GB) or ViT-H-14 (3.9 GB).

Run:
    aurum-cv-download-models clip       # one-off, downloads weights
    /opt/aurum-dl-venv/bin/python recipes/cv/05_clip_zero_shot.py [image.jpg]

Override labels:
    AURUM_CLIP_LABELS="dog,cat,bus,car" python recipes/cv/05_clip_zero_shot.py
"""
from __future__ import annotations

import os
import sys
from pathlib import Path

import open_clip
import torch
from PIL import Image

MODEL = os.environ.get("AURUM_CLIP_MODEL", "ViT-B-32")
PRETRAINED = os.environ.get("AURUM_CLIP_PRETRAINED", "laion2b_s34b_b79k")
LABELS = os.environ.get(
    "AURUM_CLIP_LABELS",
    "a photo of a bus,a photo of a car,a photo of a person,a photo of a dog,a satellite image",
).split(",")
SAMPLE_URL = "https://ultralytics.com/images/bus.jpg"


def load_image(src: str) -> Image.Image:
    if src.startswith("http"):
        import urllib.request
        tmp = Path("/tmp/aurum-clip-input.jpg")
        urllib.request.urlretrieve(src, tmp)
        src = str(tmp)
    return Image.open(src).convert("RGB")


def main() -> int:
    src = sys.argv[1] if len(sys.argv) > 1 else SAMPLE_URL
    print(f"[clip] loading {MODEL} / {PRETRAINED}")
    model, _, preprocess = open_clip.create_model_and_transforms(MODEL, pretrained=PRETRAINED)
    tokenizer = open_clip.get_tokenizer(MODEL)
    model.eval()

    device = "cuda" if torch.cuda.is_available() else "cpu"
    model = model.to(device)
    print(f"[clip] running on {device}")

    img = preprocess(load_image(src)).unsqueeze(0).to(device)
    text = tokenizer([lbl.strip() for lbl in LABELS]).to(device)

    with torch.inference_mode(), torch.amp.autocast(device_type=device.split(":")[0], enabled=device.startswith("cuda")):
        img_feat = model.encode_image(img)
        txt_feat = model.encode_text(text)
        img_feat = img_feat / img_feat.norm(dim=-1, keepdim=True)
        txt_feat = txt_feat / txt_feat.norm(dim=-1, keepdim=True)
        probs = (100.0 * img_feat @ txt_feat.T).softmax(dim=-1)

    probs = probs.cpu().squeeze(0).tolist()
    print(f"[clip] image: {src}")
    print(f"[clip] {'label':50s} {'prob':>8s}")
    print(f"[clip] {'-' * 50} {'-' * 8}")
    ranked = sorted(zip(LABELS, probs), key=lambda kv: -kv[1])
    for lbl, p in ranked:
        print(f"[clip] {lbl.strip():50s} {p:7.3%}")
    return 0


if __name__ == "__main__":
    raise SystemExit(main())
