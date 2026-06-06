"""
aurum-cv-train — train a point-cloud semantic-segmentation model INSIDE the app.

Real, runnable training: builds several labelled street scenes, extracts
geometric features, trains a small PyTorch MLP classifier, and evaluates it on a
HELD-OUT scene the model never saw (different seed = different layout). Reports
real per-class accuracy + mean IoU, saves the trained weights, and writes a PLY
of the test scene coloured by PREDICTED class so the viewer can show what the
model learned.

This is the CPU-feasible baseline. The same pipeline (features -> classifier)
swaps the MLP for a GPU deep net (PointNet/KPConv/PTv3) when GPU hardware is
present — AurumOS already ships the PyTorch stack + the MLflow tracker daemon to
log runs. Usage:
    python3 cv_train.py [--epochs N] [--out DIR]
"""
import argparse
import json
import os
import sys
import time

import numpy as np
import torch
import torch.nn as nn

sys.path.insert(0, os.path.dirname(os.path.abspath(__file__)))
import cv_dataset as ds


class PointMLP(nn.Module):
    """Per-point classifier: 8 geometric features -> class logits."""
    def __init__(self, in_dim=8, n_classes=len(ds.CLASSES)):
        super().__init__()
        self.net = nn.Sequential(
            nn.Linear(in_dim, 64), nn.ReLU(),
            nn.Linear(64, 64), nn.ReLU(),
            nn.Linear(64, 32), nn.ReLU(),
            nn.Linear(32, n_classes),
        )

    def forward(self, x):
        return self.net(x)


def build_split(seeds):
    """Features + labels for a list of scene seeds, concatenated."""
    Xs, ys = [], []
    for s in seeds:
        P, L = ds.generate_city_scene(seed=s)
        # Subsample for speed/balance (cap per scene).
        if len(P) > 60000:
            sel = np.random.default_rng(s).choice(len(P), 60000, replace=False)
            P, L = P[sel], L[sel]
        F = ds.extract_features(P)
        Xs.append(F); ys.append(L)
    return np.vstack(Xs), np.concatenate(ys)


def remap(labels):
    """Map SemClass ids -> contiguous 0..C-1 for the loss."""
    to_idx = {c: i for i, c in enumerate(ds.CLASSES)}
    return np.array([to_idx[l] for l in labels], dtype=np.int64)


def main():
    ap = argparse.ArgumentParser()
    ap.add_argument("--epochs", type=int, default=60)
    ap.add_argument("--out", default="/tmp/aurum/cvmodel")
    args = ap.parse_args()
    os.makedirs(args.out, exist_ok=True)
    torch.manual_seed(0); np.random.seed(0)

    print("[cv-train] building training scenes (seeds 1-4)...", flush=True)
    Xtr, ytr = build_split([1, 2, 3, 4])
    print(f"[cv-train] building HELD-OUT test scene (seed 99)...", flush=True)
    Xte, yte = build_split([99])

    # Standardise features on train stats.
    mu, sd = Xtr.mean(0), Xtr.std(0) + 1e-6
    Xtr = (Xtr - mu) / sd
    Xte = (Xte - mu) / sd

    ytr_i = remap(ytr); yte_i = remap(yte)
    # Class weights (cars/poles are rare) so they aren't ignored.
    counts = np.bincount(ytr_i, minlength=len(ds.CLASSES)).astype(np.float32)
    weights = torch.tensor((counts.sum() / (counts + 1)).astype(np.float32))

    Xtr_t = torch.tensor(Xtr); ytr_t = torch.tensor(ytr_i)
    Xte_t = torch.tensor(Xte)

    model = PointMLP()
    opt = torch.optim.Adam(model.parameters(), lr=1e-3)
    lossf = nn.CrossEntropyLoss(weight=weights)

    n = len(Xtr_t); bs = 8192
    history = []
    t0 = time.time()
    for ep in range(args.epochs):
        model.train()
        perm = torch.randperm(n)
        tot = 0.0
        for i in range(0, n, bs):
            idx = perm[i:i + bs]
            opt.zero_grad()
            out = model(Xtr_t[idx])
            loss = lossf(out, ytr_t[idx])
            loss.backward(); opt.step()
            tot += float(loss) * len(idx)
        ep_loss = tot / n
        history.append(ep_loss)
        if ep % 10 == 0 or ep == args.epochs - 1:
            print(f"[cv-train] epoch {ep:3d}  loss {ep_loss:.4f}", flush=True)

    # Evaluate on the held-out scene.
    model.eval()
    with torch.no_grad():
        pred = model(Xte_t).argmax(1).numpy()
    idx_to_cls = {i: c for i, c in enumerate(ds.CLASSES)}
    pred_cls = np.array([idx_to_cls[p] for p in pred])

    # Metrics: overall acc, per-class IoU, mean IoU.
    overall = float((pred == yte_i).mean())
    ious = {}
    for i, c in enumerate(ds.CLASSES):
        inter = np.sum((pred == i) & (yte_i == i))
        union = np.sum((pred == i) | (yte_i == i))
        ious[ds.CLASS_NAMES[c]] = float(inter / union) if union else 0.0
    miou = float(np.mean(list(ious.values())))

    print(f"\n[cv-train] === RESULTS on held-out scene (seed 99) ===")
    print(f"[cv-train] overall accuracy: {overall*100:.1f}%")
    print(f"[cv-train] mean IoU:         {miou*100:.1f}%")
    for k, v in ious.items():
        print(f"[cv-train]   IoU {k:11s} {v*100:5.1f}%")
    print(f"[cv-train] trained in {time.time()-t0:.1f}s on CPU")

    # Save model + the predicted test scene (for the viewer).
    torch.save({"state": model.state_dict(), "mu": mu, "sd": sd}, f"{args.out}/model.pt")
    Pte, _ = ds.generate_city_scene(seed=99)
    if len(Pte) > 60000:
        sel = np.random.default_rng(99).choice(len(Pte), 60000, replace=False)
        Pte = Pte[sel]
    ds.save_ply_labeled(Pte, pred_cls, f"{args.out}/pred_scene.ply")
    ds.save_ply_labeled(Pte, yte, f"{args.out}/truth_scene.ply")
    json.dump({"overall": overall, "miou": miou, "iou": ious, "loss": history},
              open(f"{args.out}/metrics.json", "w"), indent=2)
    print(f"[cv-train] saved model + pred_scene.ply + truth_scene.ply to {args.out}")


if __name__ == "__main__":
    main()
