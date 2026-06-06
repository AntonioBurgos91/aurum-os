"""
Synthetic labelled street scenes + geometric per-point features for point-cloud
semantic segmentation. This is the data side of the in-app CV trainer.

The scene generator mirrors the C++ generate_city_scene() (ground, sidewalks,
buildings, cars, trees, poles) but in Python so we can spawn many independent
scenes for train/validation/test. Different seeds = different layouts, so the
model is evaluated on geometry it never saw.

Features are the classic eigenvalue-based descriptors used in point-cloud
semantic classification (Weinmann et al.): from each point's local
neighbourhood covariance we derive linearity / planarity / scattering /
verticality / height, which separate flat ground, vertical facades, blobby
vegetation, box-like cars and thin poles. A deep model (PointNet/KPConv/PTv3)
would *learn* features instead; this hand-crafted set is a real, fast baseline
that runs on CPU and keeps the demo end-to-end runnable without a GPU.
"""
import numpy as np

# Class ids must match the C++ SemClass enum.
GROUND, SIDEWALK, BUILDING, VEGETATION, CAR, POLE = 1, 2, 3, 4, 5, 6
CLASS_NAMES = {GROUND: "Suelo", SIDEWALK: "Acera", BUILDING: "Edificio",
               VEGETATION: "Vegetacion", CAR: "Coche", POLE: "Poste"}
CLASSES = [GROUND, SIDEWALK, BUILDING, VEGETATION, CAR, POLE]


def generate_city_scene(length_m=50, width_m=16, seed=7):
    rng = np.random.default_rng(seed)
    pts, lbl = [], []

    def add(arr, cls):
        pts.append(arr)
        lbl.append(np.full(len(arr), cls, dtype=np.int64))

    road_half, walk_w = 4.0, 2.0

    # Ground + sidewalks
    n_ground = int(length_m * width_m * 60)
    x = rng.uniform(0, length_m, n_ground)
    y = rng.uniform(-width_m / 2, width_m / 2, n_ground)
    z = rng.normal(0, 0.01, n_ground)
    ay = np.abs(y)
    on_road = ay <= road_half
    on_walk = (ay > road_half) & (ay <= road_half + walk_w)
    keep = on_road | on_walk
    x, y, z, ay = x[keep], y[keep], z[keep], ay[keep]
    z = np.where(ay > road_half, z + 0.12, z)  # kerb step
    cls = np.where(ay > road_half, SIDEWALK, GROUND)
    add(np.column_stack([x, y, z]), 0)
    lbl[-1] = cls

    facade_y = road_half + walk_w
    # Buildings both sides
    for side in (-1, 1):
        bx0 = 0.0
        while bx0 < length_m:
            bw = rng.uniform(6, 14)
            bh = rng.uniform(6, 20)
            n = int(bw * bh * 25)
            px = bx0 + rng.uniform(0, bw, n)
            py = side * (facade_y + rng.uniform(0, 0.4, n))
            pz = rng.uniform(0, bh, n)
            add(np.column_stack([px, py, pz]), BUILDING)
            bx0 += bw + rng.uniform(0.5, 2.0)

    # Parked cars
    for side in (-1, 1):
        cx0 = 5.0
        while cx0 < length_m - 5:
            if rng.random() < 0.6:
                L, W, H = 4.2, 1.8, 1.45
                cy = side * (road_half - 1.0)
                n = 1800
                px = cx0 + rng.uniform(0, L, n)
                py = cy + rng.uniform(-W / 2, W / 2, n)
                pz = 0.2 + rng.uniform(0, H, n)
                add(np.column_stack([px, py, pz]), CAR)
            cx0 += rng.uniform(6, 10)

    # Trees (trunk + canopy)
    for side in (-1, 1):
        tx = 8.0
        while tx < length_m:
            ty = side * (road_half + walk_w / 2)
            ntr = 250
            add(np.column_stack([tx + rng.normal(0, 0.05, ntr),
                                 ty + rng.normal(0, 0.05, ntr),
                                 rng.uniform(0, 2.2, ntr)]), VEGETATION)
            ncan = 1800
            u = rng.uniform(0, 2 * np.pi, ncan)
            v = np.arccos(rng.uniform(-1, 1, ncan))
            r = 1.6 * np.cbrt(rng.uniform(0, 1, ncan))
            add(np.column_stack([tx + r * np.sin(v) * np.cos(u),
                                 ty + r * np.sin(v) * np.sin(u),
                                 3.0 + r * np.cos(v)]), VEGETATION)
            tx += rng.uniform(12, 18)

    # Lamp posts
    for side in (-1, 1):
        px0 = 14.0
        while px0 < length_m:
            py = side * (road_half + walk_w * 0.8)
            n = 350
            add(np.column_stack([px0 + rng.normal(0, 0.03, n),
                                 py + rng.normal(0, 0.03, n),
                                 rng.uniform(0, 5.0, n)]), POLE)
            px0 += 18.0

    P = np.vstack(pts).astype(np.float32)
    L = np.concatenate(lbl).astype(np.int64)
    return P, L


def extract_features(P, k=18):
    """Per-point geometric features from the local k-NN covariance."""
    from sklearn.neighbors import NearestNeighbors
    n = len(P)
    nn = NearestNeighbors(n_neighbors=k).fit(P)
    _, idx = nn.kneighbors(P)
    feats = np.zeros((n, 8), dtype=np.float32)
    # Precompute neighbourhoods in a vectorised-ish loop.
    nbr = P[idx]                      # (n, k, 3)
    mean = nbr.mean(axis=1, keepdims=True)
    cen = nbr - mean
    cov = np.einsum('nki,nkj->nij', cen, cen) / k   # (n,3,3)
    # Eigenvalues sorted desc.
    evals = np.linalg.eigvalsh(cov)               # ascending
    evals = np.clip(evals[:, ::-1], 1e-8, None)   # desc: l1>=l2>=l3
    l1, l2, l3 = evals[:, 0], evals[:, 1], evals[:, 2]
    s = l1 + l2 + l3
    linearity = (l1 - l2) / l1
    planarity = (l2 - l3) / l1
    scattering = l3 / l1
    # Verticality from the smallest-eigenvalue direction (normal): use |normal_z|.
    # Recompute eigenvectors for normal (smallest eval direction).
    w, vses = np.linalg.eigh(cov)
    normal = vses[:, :, 0]            # smallest eval eigenvector
    verticality = 1.0 - np.abs(normal[:, 2])
    height = P[:, 2]
    # Local height spread.
    zspread = nbr[:, :, 2].max(axis=1) - nbr[:, :, 2].min(axis=1)
    feats[:, 0] = linearity
    feats[:, 1] = planarity
    feats[:, 2] = scattering
    feats[:, 3] = verticality
    feats[:, 4] = height
    feats[:, 5] = zspread
    feats[:, 6] = s            # local "roughness" / point spread
    feats[:, 7] = np.abs(P[:, 1])  # lateral distance from street centre
    return feats


def save_ply_labeled(P, labels, path):
    with open(path, "w") as f:
        f.write("ply\nformat ascii 1.0\n")
        f.write(f"element vertex {len(P)}\n")
        f.write("property float x\nproperty float y\nproperty float z\n")
        f.write("property float defect\nproperty int label\n")
        f.write("end_header\n")
        for (x, y, z), l in zip(P, labels):
            f.write(f"{x} {y} {z} 0 {int(l)}\n")
