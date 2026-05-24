#!/usr/bin/env python3
"""SAM2 segmentation — AurumOS reference recipe.

Loads the SAM2 model size matching the AurumOS profile, runs automatic mask
generation on a sample image, and saves the resulting overlay.

Profile mapping (AURUM_SAM_MODEL):
    lite        → sam2-tiny  (smallest hiera variant)
    standard    → sam2-base  (sam2-hiera-base-plus)
    pro         → sam2-large
    workstation → sam2-large

The SAM2 pip package's canonical name has flipped twice (sam-2 vs
segment-anything-2). Both ship `sam2` as the import name, which is what we
use here — works regardless of which pip name was resolved.

Run:
    aurum-cv-download-models sam       # one-off, downloads weights
    /opt/aurum-dl-venv/bin/python recipes/cv/03_sam2_segment.py [image.jpg]
"""
from __future__ import annotations

import os
import sys
from pathlib import Path

import numpy as np
from PIL import Image

# Map AurumOS symbolic name to the HF model id used by sam2's loader. Same
# mapping as aurum-cv-download-models.
SAM_MODEL = os.environ.get("AURUM_SAM_MODEL", "sam2-base")
HF_ID = {
    "sam2-tiny":  "facebook/sam2-hiera-tiny",
    "sam2-base":  "facebook/sam2-hiera-base-plus",
    "sam2-large": "facebook/sam2-hiera-large",
}.get(SAM_MODEL, SAM_MODEL)

# Default sample image — same one ultralytics ships, so we don't need a second
# fixture in the repo. Argv overrides.
SAMPLE_URL = "https://ultralytics.com/images/bus.jpg"


def load_image(src: str) -> np.ndarray:
    if src.startswith("http"):
        import urllib.request
        tmp = Path("/tmp/aurum-sam-input.jpg")
        urllib.request.urlretrieve(src, tmp)
        src = str(tmp)
    return np.array(Image.open(src).convert("RGB"))


def main() -> int:
    src = sys.argv[1] if len(sys.argv) > 1 else SAMPLE_URL
    out_dir = Path(os.environ.get("AURUM_CV_OUT", "~/cv-out/sam2")).expanduser()
    out_dir.mkdir(parents=True, exist_ok=True)

    img = load_image(src)
    print(f"[sam2] input image shape: {img.shape}")
    print(f"[sam2] loading model: {HF_ID}")

    # Two loader paths exist depending on which sam2 pip the user got:
    #   * facebookresearch fork: from sam2.build_sam import build_sam2
    #   * the HF-friendly fork:  from sam2.sam2_image_predictor import SAM2ImagePredictor
    # We prefer the HF-friendly path because it accepts a hf_hub_download
    # snapshot directly and matches the AutoMaskGenerator API.
    from sam2.automatic_mask_generator import SAM2AutomaticMaskGenerator
    from sam2.sam2_image_predictor import SAM2ImagePredictor

    predictor = SAM2ImagePredictor.from_pretrained(HF_ID)
    mask_gen = SAM2AutomaticMaskGenerator(predictor.model)

    masks = mask_gen.generate(img)
    print(f"[sam2] generated {len(masks)} masks")

    # Overlay: paint each mask with a random colour at alpha 0.5.
    overlay = img.astype(np.float32).copy()
    rng = np.random.default_rng(0)
    for m in masks:
        seg = m["segmentation"]
        color = rng.integers(64, 255, size=3).astype(np.float32)
        overlay[seg] = 0.5 * overlay[seg] + 0.5 * color

    out = out_dir / "overlay.png"
    Image.fromarray(overlay.astype(np.uint8)).save(out)
    print(f"[sam2] overlay saved: {out}")
    return 0


if __name__ == "__main__":
    raise SystemExit(main())
