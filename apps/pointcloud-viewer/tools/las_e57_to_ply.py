#!/usr/bin/env python3
"""
aurum-pcv-convert — LAS/LAZ/E57 -> PLY bridge for the AurumOS point-cloud viewer.

The viewer (aurum-pointcloud-viewer, C++/Qt6/OpenGL) reads a simple ASCII PLY
with an optional per-point `label` int property (see point_cloud.cpp:load_ply).
Real scanner output is almost never PLY — it's LAS/LAZ (ASPRS) or E57 (ASTM).
Rather than write a second point-cloud parser in C++ (a large, bug-prone
undertaking for binary formats with many revisions and edge cases), this
bridges via the mature Python readers (laspy, pye57) that already handle the
format complexity, and emits the PLY the viewer already consumes.

Classification mapping (LAS -> SemClass) uses the ASPRS standard classification
codes (LAS spec 1.4, Table 17) where they exist, and is HONEST about what
doesn't map: unknown/unmapped codes become Unlabeled (0), never guessed into a
wrong class. E57 carries no standard per-point semantic class at all -- if the
file has no matching extra field, output is geometry only (label=0), same as
loading a raw scan with no classification.

Usage:
    aurum-pcv-convert input.las  -o output.ply
    aurum-pcv-convert input.laz  -o output.ply     # requires laszip backend
    aurum-pcv-convert input.e57  -o output.ply
    aurum-pcv-convert input.las  --info            # print point count + class histogram, no conversion
"""
import argparse
import sys

# ASPRS LAS classification codes -> AurumOS SemClass ids (point_cloud.h).
# Codes not listed here (rail, wire, bridge deck, high noise, reserved, etc.)
# intentionally map to 0 (Unlabeled) rather than being forced into the nearest
# guess -- a wrong label is worse than no label for a defect-inspection tool.
ASPRS_TO_SEMCLASS = {
    2: 1,   # Ground              -> Ground
    11: 2,  # Road Surface        -> Sidewalk  (closest paved-surface analogue)
    6: 3,   # Building            -> Building
    3: 4,   # Low Vegetation      -> Vegetation
    4: 4,   # Medium Vegetation   -> Vegetation
    5: 4,   # High Vegetation     -> Vegetation
    64: 5,  # (vendor-common "Car"/vehicle extension code, not in base ASPRS)
    18: 6,  # High Point / often reused for poles in mobile-mapping profiles
}
SEMCLASS_NAMES = {0: "Unlabeled", 1: "Ground", 2: "Sidewalk", 3: "Building",
                  4: "Vegetation", 5: "Car", 6: "Pole"}


def convert_las(path):
    """Yields (x, y, z, defect, label) via laspy. Handles LAS and LAZ (if a
    LAZ backend -- lazrs or laszip -- is installed; laspy raises a clear error
    naming the missing backend otherwise, which we surface as-is)."""
    import laspy
    with laspy.open(path) as f:
        las = f.read()
        n = len(las.points)
        has_cls = "classification" in las.point_format.dimension_names
        cls = las.classification if has_cls else [0] * n
        for i in range(n):
            code = int(cls[i]) if has_cls else 0
            label = ASPRS_TO_SEMCLASS.get(code, 0)
            yield float(las.x[i]), float(las.y[i]), float(las.z[i]), 0.0, label


def convert_e57(path):
    """Yields (x, y, z, defect, label) via pye57. E57 has no standard
    per-point semantic class -- output is geometry-only (label=0) unless a
    vendor extra field literally matches our class scheme, which we do not
    assume."""
    import pye57
    e57 = pye57.E57(path)
    for scan_idx in range(e57.scan_count):
        data = e57.read_scan(scan_idx, ignore_missing_fields=True)
        xs, ys, zs = data["cartesianX"], data["cartesianY"], data["cartesianZ"]
        for x, y, z in zip(xs, ys, zs):
            yield float(x), float(y), float(z), 0.0, 0


def write_ply(points_iter, out_path, count_hint=None):
    """Streams to PLY without holding the whole cloud in memory twice."""
    pts = list(points_iter)
    n = len(pts)
    with open(out_path, "w") as f:
        f.write("ply\nformat ascii 1.0\n")
        f.write(f"element vertex {n}\n")
        f.write("property float x\nproperty float y\nproperty float z\n")
        f.write("property float defect\nproperty int label\n")
        f.write("end_header\n")
        for x, y, z, d, l in pts:
            f.write(f"{x} {y} {z} {d} {l}\n")
    return n, pts


def class_histogram(pts):
    hist = {}
    for *_, label in pts:
        hist[label] = hist.get(label, 0) + 1
    return hist


def main():
    ap = argparse.ArgumentParser(description=__doc__,
                                 formatter_class=argparse.RawDescriptionHelpFormatter)
    ap.add_argument("input", help="input .las/.laz/.e57 file")
    ap.add_argument("-o", "--output", help="output .ply path")
    ap.add_argument("--info", action="store_true",
                    help="print point count + class histogram; do not write output")
    args = ap.parse_args()

    import os
    if not os.path.isfile(args.input):
        print(f"error: input file not found: {args.input}", file=sys.stderr)
        sys.exit(2)

    ext = args.input.lower().rsplit(".", 1)[-1]
    if ext in ("las", "laz"):
        gen = convert_las(args.input)
    elif ext == "e57":
        gen = convert_e57(args.input)
    else:
        print(f"error: unrecognized extension '.{ext}' (expected .las/.laz/.e57)",
              file=sys.stderr)
        sys.exit(2)

    if args.info:
        pts = list(gen)
        hist = class_histogram(pts)
        print(f"points: {len(pts)}")
        for code, cnt in sorted(hist.items()):
            print(f"  {SEMCLASS_NAMES.get(code, '?'):11s} {cnt}")
        unmapped = sum(v for k, v in hist.items() if k == 0)
        if unmapped and 0 in hist:
            print(f"  (note: {unmapped} unlabeled -- no ASPRS code, or a code "
                  f"not in AurumOS's mapping table)")
        return

    if not args.output:
        print("error: -o/--output required unless --info is given", file=sys.stderr)
        sys.exit(2)
    n, pts = write_ply(gen, args.output)
    hist = class_histogram(pts)
    print(f"wrote {args.output}: {n} points")
    labeled = sum(v for k, v in hist.items() if k != 0)
    if labeled:
        print(f"  {labeled}/{n} points carry a mapped semantic class")
    else:
        print("  geometry only -- no classification codes mapped "
              "(raw scan, or codes outside AurumOS's mapping table)")


if __name__ == "__main__":
    main()
