"""
CI smoke test for the LAS/E57 -> PLY conversion bridge (aurum-pcv-convert).
Writes a real binary LAS file (via laspy), converts it, and asserts the PLY
contract the C++ viewer's load_ply() depends on: correct point count, correct
ASPRS-classification -> SemClass mapping, and unmapped codes staying
Unlabeled rather than being guessed into a wrong class.
"""
import os
import subprocess
import sys
import tempfile

import numpy as np
import laspy

sys.path.insert(0, os.path.dirname(os.path.abspath(__file__)))
import las_e57_to_ply as conv


def _write_las(path, n=2000, seed=1, with_classification=True):
    header = laspy.LasHeader(version="1.4", point_format=6)
    header.scales = [0.001, 0.001, 0.001]
    las = laspy.LasData(header)
    rng = np.random.default_rng(seed)
    las.x = rng.uniform(0, 30, n)
    las.y = rng.uniform(-8, 8, n)
    las.z = rng.uniform(0, 5, n)
    if with_classification:
        # Mix of mapped (2=ground, 6=building, 5=veg) and an unmapped code (7=noise).
        codes = rng.choice([2, 6, 5, 7], size=n, p=[0.4, 0.3, 0.2, 0.1])
        las.classification = codes.astype(np.uint8)
    las.write(path)
    return n


def test_classified_las_maps_correctly():
    with tempfile.TemporaryDirectory() as d:
        las_path = os.path.join(d, "t.las")
        n = _write_las(las_path, n=3000, seed=7)
        pts = list(conv.convert_las(las_path))
        assert len(pts) == n
        hist = conv.class_histogram(pts)
        # Mapped codes present, unmapped code (7=noise) -> Unlabeled(0), not guessed.
        assert hist.get(1, 0) > 0, "Ground (code 2) not mapped"
        assert hist.get(3, 0) > 0, "Building (code 6) not mapped"
        assert hist.get(4, 0) > 0, "Vegetation (code 5) not mapped"
        assert hist.get(0, 0) > 0, "unmapped code 7 should fall to Unlabeled"
        print(f"ok classified LAS: {n} pts, histogram={hist}")


def test_unclassified_las_is_all_unlabeled():
    with tempfile.TemporaryDirectory() as d:
        las_path = os.path.join(d, "raw.las")
        n = _write_las(las_path, n=500, seed=2, with_classification=False)
        pts = list(conv.convert_las(las_path))
        hist = conv.class_histogram(pts)
        assert hist == {0: n}, f"raw scan should be 100% Unlabeled, got {hist}"
        print(f"ok raw LAS: {n} pts, all Unlabeled (honest, no guessing)")


def test_ply_round_trip_and_cli():
    with tempfile.TemporaryDirectory() as d:
        las_path = os.path.join(d, "t.las")
        n = _write_las(las_path, n=1000, seed=3)
        ply_path = os.path.join(d, "out.ply")
        r = subprocess.run(
            [sys.executable, os.path.join(os.path.dirname(__file__), "las_e57_to_ply.py"),
             las_path, "-o", ply_path],
            capture_output=True, text=True, timeout=60)
        assert r.returncode == 0, f"CLI failed: {r.stdout}\n{r.stderr}"
        assert os.path.getsize(ply_path) > 0
        with open(ply_path) as f:
            header = [next(f) for _ in range(8)]
        assert f"element vertex {n}\n" in header
        assert "property float defect\n" in header
        assert "property int label\n" in header
        print(f"ok PLY output: {n} points, contract-correct header")


def test_missing_file_errors_cleanly():
    r = subprocess.run(
        [sys.executable, os.path.join(os.path.dirname(__file__), "las_e57_to_ply.py"),
         "/nonexistent/path.las", "--info"],
        capture_output=True, text=True, timeout=10)
    assert r.returncode == 2
    assert "not found" in r.stderr
    print("ok missing-file error is clean (no traceback)")


def test_unrecognized_extension_errors_cleanly():
    r = subprocess.run(
        [sys.executable, os.path.join(os.path.dirname(__file__), "las_e57_to_ply.py"),
         __file__, "--info"],  # a real file, wrong extension (.py)
        capture_output=True, text=True, timeout=10)
    assert r.returncode == 2
    assert "unrecognized extension" in r.stderr
    print("ok unrecognized-extension error is clean")


if __name__ == "__main__":
    test_classified_las_maps_correctly()
    test_unclassified_las_is_all_unlabeled()
    test_ply_round_trip_and_cli()
    test_missing_file_errors_cleanly()
    test_unrecognized_extension_errors_cleanly()
    print("SMOKE OK")
