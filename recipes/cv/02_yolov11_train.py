#!/usr/bin/env python3
"""YOLOv11 fine-tune on COCO128 — AurumOS reference recipe.

COCO128 is the standard 128-image "is the trainer wired up?" smoke set that
ultralytics ships in their data registry. It downloads on first use (<10 MB)
and trains in 1-3 minutes on an 8 GB GPU, 5-15 minutes on CPU.

For real fine-tunes, swap DATA= to your own dataset.yaml. The trainer config
below is profile-tuned: batch size shrinks on lite, expands on workstation.

Run:
    /opt/aurum-dl-venv/bin/python recipes/cv/02_yolov11_train.py
"""
from __future__ import annotations

import os
from pathlib import Path

from ultralytics import YOLO

# We always START from the AurumOS profile size; users can override.
MODEL_NAME = os.environ.get("AURUM_YOLO_MODEL", "yolov11s")
if not MODEL_NAME.endswith(".pt"):
    MODEL_NAME = f"{MODEL_NAME}.pt"

# Ultralytics resolves 'coco128.yaml' from its built-in dataset registry and
# downloads the images on demand.
DATA = os.environ.get("AURUM_CV_DATASET", "coco128.yaml")

# Profile-aware hyperparameters. EPOCHS stays small (this is a smoke recipe);
# tune up for production runs.
PROFILE = os.environ.get("AURUM_PROFILE", "standard")
BATCH = {"lite": 4, "standard": 16, "pro": 32, "workstation": 64}.get(PROFILE, 16)
IMGSZ = 640
EPOCHS = int(os.environ.get("AURUM_CV_EPOCHS", "3"))
DEVICE = os.environ.get("AURUM_CV_DEVICE", "")  # "" → autodetect cuda/mps/cpu


def main() -> int:
    out_dir = Path(os.environ.get("AURUM_CV_OUT", "~/cv-out/yolo-train")).expanduser()
    out_dir.mkdir(parents=True, exist_ok=True)

    print(f"[yolo-train] profile={PROFILE} model={MODEL_NAME} data={DATA}")
    print(f"[yolo-train] epochs={EPOCHS} batch={BATCH} imgsz={IMGSZ}")

    model = YOLO(MODEL_NAME)

    # train() blocks until done and returns a metrics object. Tensorboard logs
    # land under project/name/.
    train_kwargs = {
        "data": DATA,
        "epochs": EPOCHS,
        "imgsz": IMGSZ,
        "batch": BATCH,
        "project": str(out_dir),
        "name": "run",
        "exist_ok": True,
    }
    if DEVICE:
        train_kwargs["device"] = DEVICE

    metrics = model.train(**train_kwargs)
    print("[yolo-train] training complete")
    print(f"[yolo-train] best mAP50: {metrics.box.map50:.4f}")
    print(f"[yolo-train] weights at: {out_dir}/run/weights/best.pt")
    return 0


if __name__ == "__main__":
    raise SystemExit(main())
