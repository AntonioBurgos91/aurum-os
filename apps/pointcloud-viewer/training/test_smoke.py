"""
CI smoke test for the CV training pipeline. Trains a tiny run end-to-end
(small scanned scene, 2 epochs) and asserts the pipeline's contract: scenes
generate with all classes, the LiDAR sim actually occludes, features have the
right shape, training runs, and the output artifacts (model, PLYs, metrics,
confusion) exist and are self-consistent. Runtime target: <60s CPU.

Run:  python3 test_smoke.py   (exit 0 = pass)
"""
import json
import os
import subprocess
import sys
import tempfile

import numpy as np

sys.path.insert(0, os.path.dirname(os.path.abspath(__file__)))
import cv_dataset as ds


def test_scene_and_scan():
    P, L = ds.generate_city_scene(length_m=20, width_m=12, seed=5)
    assert len(P) > 5000 and len(P) == len(L)
    present = set(np.unique(L).tolist())
    for c in ds.CLASSES:
        assert c in present, f"clase ausente en escena: {ds.CLASS_NAMES[c]}"
    Ps, Ls = ds.simulate_lidar_scan(P, L, length_m=20)
    assert 0.2 < len(Ps) / len(P) < 0.98, "el escaneo LiDAR no ocluye (o borra todo)"
    F = ds.extract_features(Ps[:2000], k=10)
    assert F.shape == (2000, 8) and np.isfinite(F).all()
    print(f"ok scene+scan: {len(P)} -> {len(Ps)} pts, features finitas")


def test_training_end_to_end():
    out = tempfile.mkdtemp(prefix="cvsmoke-")
    env = dict(os.environ, AURUM_SMOKE="1")
    r = subprocess.run(
        [sys.executable, os.path.join(os.path.dirname(__file__), "cv_train.py"),
         "--epochs", "2", "--out", out, "--smoke"],
        capture_output=True, text=True, timeout=600, env=env)
    assert r.returncode == 0, f"cv_train fallo:\n{r.stdout[-2000:]}\n{r.stderr[-2000:]}"
    for f in ("model.pt", "pred_scene.ply", "truth_scene.ply",
              "error_scene.ply", "metrics.json", "confusion.json"):
        p = os.path.join(out, f)
        assert os.path.getsize(p) > 0, f"artefacto vacio/ausente: {f}"
    m = json.load(open(os.path.join(out, "metrics.json")))
    assert 0.0 <= m["miou"] <= 1.0 and 0.0 <= m["overall"] <= 1.0
    assert len(m["loss"]) == 2, "epochs no respetadas"
    cm = json.load(open(os.path.join(out, "confusion.json")))
    total = sum(sum(row) for row in cm["confusion"])
    assert total > 1000, "matriz de confusion vacia"
    print(f"ok training e2e: mIoU={m['miou']:.2f} overall={m['overall']:.2f}")


if __name__ == "__main__":
    test_scene_and_scan()
    test_training_end_to_end()
    print("SMOKE OK")
