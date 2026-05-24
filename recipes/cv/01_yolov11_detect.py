#!/usr/bin/env python3
"""YOLOv11 object detection — AurumOS reference recipe.

Loads the model whose size matches the AurumOS profile (yolov11n/s/m/l/x),
runs it against a sample image, and prints the detected classes + bboxes.

Profile mapping (read from /etc/aurum/profile.conf via AURUM_YOLO_MODEL):
    lite        → yolov11n   (CPU-friendly, ~3 MB weights)
    standard    → yolov11s   (8 GB VRAM target)
    pro         → yolov11m
    workstation → yolov11x   (largest, best accuracy)

Run:
    /opt/aurum-dl-venv/bin/python recipes/cv/01_yolov11_detect.py
    AURUM_YOLO_MODEL=yolov11n python recipes/cv/01_yolov11_detect.py path/to/img.jpg

First run downloads weights to ~/.cache/torch/hub/checkpoints/.
"""
from __future__ import annotations

import os
import sys
from pathlib import Path

# Ultralytics is the canonical YOLOv11 pkg. Wave 7 installed it; recipes pin
# the floor in pip-requirements-cv.txt.
from ultralytics import YOLO

MODEL_NAME = os.environ.get("AURUM_YOLO_MODEL", "yolov11s")
# Ultralytics accepts a bare size token or a .pt filename. Normalise here.
if not MODEL_NAME.endswith(".pt"):
    MODEL_NAME = f"{MODEL_NAME}.pt"

# Default sample: ultralytics ships a built-in bus.jpg in their assets. Users
# can override with argv[1] (any image path or URL).
SAMPLE = "https://ultralytics.com/images/bus.jpg"


def main() -> int:
    source = sys.argv[1] if len(sys.argv) > 1 else SAMPLE
    out_dir = Path(os.environ.get("AURUM_CV_OUT", "~/cv-out/yolo-detect")).expanduser()
    out_dir.mkdir(parents=True, exist_ok=True)

    print(f"[yolo] loading model: {MODEL_NAME}")
    model = YOLO(MODEL_NAME)

    print(f"[yolo] running detection on: {source}")
    results = model.predict(source=source, save=True, project=str(out_dir), name="run")

    # `results` is a list (one Results per input image). Each carries .boxes
    # (xyxy + confidence + class id) which is what most downstream consumers
    # actually want.
    for i, r in enumerate(results):
        n = 0 if r.boxes is None else len(r.boxes)
        print(f"[yolo] image {i}: {n} detection(s)")
        if r.boxes is None:
            continue
        names = r.names  # {class_id: class_name}
        for b in r.boxes:
            cls = int(b.cls.item())
            conf = float(b.conf.item())
            xyxy = [round(float(v), 1) for v in b.xyxy[0].tolist()]
            print(f"    {names[cls]:15s} conf={conf:.3f} bbox={xyxy}")

    print(f"[yolo] annotated images saved under {out_dir}")
    return 0


if __name__ == "__main__":
    sys.exit(main())
