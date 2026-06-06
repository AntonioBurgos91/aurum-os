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

    # --- CONFUSERS (make the problem realistic) ---
    # Low hedges along the sidewalk: blobby + low, geometrically close to cars
    # and to vegetation -> a genuine source of confusion (labelled VEGETATION).
    for side in (-1, 1):
        hx = 6.0
        while hx < length_m:
            if rng.random() < 0.5:
                L = rng.uniform(2.0, 4.0)
                hy = side * (road_half + walk_w + 0.2)
                n = 1500
                add(np.column_stack([hx + rng.uniform(0, L, n),
                                     hy + rng.normal(0, 0.25, n),
                                     rng.uniform(0, 0.9, n)]), VEGETATION)
            hx += rng.uniform(7, 12)
    # Low garden walls at the building line: short vertical slabs, easy to
    # confuse with building bases / cars (labelled BUILDING).
    for side in (-1, 1):
        wx = 4.0
        while wx < length_m:
            if rng.random() < 0.4:
                L = rng.uniform(3.0, 6.0)
                wy = side * (road_half + walk_w + 0.1)
                n = 1200
                add(np.column_stack([wx + rng.uniform(0, L, n),
                                     wy + rng.normal(0, 0.08, n),
                                     rng.uniform(0, 1.0, n)]), BUILDING)
            wx += rng.uniform(8, 14)

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


# ── Realistic LiDAR scan simulation ─────────────────────────────────────────
# The dense scene above is the "ground-truth world". A real mobile scanner only
# captures what its beams hit: occlusion (shadows behind cars/trees), density
# that falls with range, and per-point noise. simulate_lidar_scan() reproduces
# this with angular binning from scanner positions along the street — the same
# physics a 360° LiDAR obeys — turning the clean world into a realistic,
# hard-to-segment scan. This is what makes the mini case "real".

def simulate_lidar_scan(P, L, length_m=50, az_res_deg=0.45, el_res_deg=0.9,
                        noise_m=0.02, seed=0):
    rng = np.random.default_rng(seed)
    # Scanner trajectory: down the street centreline at 1.6 m height, every 3 m.
    origins = [np.array([x, 0.0, 1.6], np.float32)
               for x in np.arange(3.0, length_m, 6.0)]
    az_res = np.deg2rad(az_res_deg)
    el_res = np.deg2rad(el_res_deg)
    keep_mask = np.zeros(len(P), dtype=bool)

    for o in origins:
        vec = P - o
        rng_d = np.linalg.norm(vec, axis=1)
        good = rng_d > 0.2
        az = np.arctan2(vec[:, 1], vec[:, 0])
        el = np.arcsin(np.clip(vec[:, 2] / np.maximum(rng_d, 1e-6), -1, 1))
        az_bin = np.round(az / az_res).astype(np.int64)
        el_bin = np.round(el / el_res).astype(np.int64)
        # Only points within a sensible range of this scan position.
        good &= rng_d < 22.0
        idx = np.where(good)[0]
        if len(idx) == 0:
            continue
        key = az_bin[idx].astype(np.int64) * 100000 + el_bin[idx]
        order = np.lexsort((rng_d[idx], key))  # by bin, then nearest range
        ks = key[order]
        first = np.ones(len(ks), bool)
        first[1:] = ks[1:] != ks[:-1]
        keep_mask[idx[order[first]]] = True  # nearest point per angular bin

    Pk = P[keep_mask].copy()
    Lk = L[keep_mask].copy()
    # Per-point sensor noise (range/beam jitter).
    Pk += rng.normal(0, noise_m, Pk.shape).astype(np.float32)
    return Pk, Lk


def generate_scanned_scene(seed=7, hard=False):
    """A full ground-truth world, then a realistic LiDAR scan of it."""
    # 'hard' varies layout so the test scene differs from training in geometry.
    length = 60 if hard else 50
    width = 18 if hard else 16
    P, L = generate_city_scene(length_m=length, width_m=width, seed=seed)
    Ps, Ls = simulate_lidar_scan(P, L, length_m=length,
                                 az_res_deg=1.1 if hard else 1.0,
                                 el_res_deg=1.8 if hard else 1.6,
                                 noise_m=0.035 if hard else 0.03, seed=seed)
    return Ps, Ls
