# AurumOS — Point Cloud Viewer (prototype)

Native Qt6/OpenGL 3D point-cloud viewer for road-defect inspection: loads a
scan (PLY) and shades each point by a defect score (green healthy → red severe
pothole), the same signal a detector produces. Built to evaluate AurumOS as a
host for computer-vision / point-cloud workloads.

## Targets
- `aurum-pointcloud-viewer` — interactive window (orbit, zoom, point size 1/2/3).
- `pcv-render-offscreen <out.png> [in.ply]` — headless render (CI / servers).
- `test_point_cloud` — unit tests (bounds, defect colour, PLY round-trip, scan).

## Build
```
cmake -S . -B build -DBUILD_TESTS=ON -DCMAKE_BUILD_TYPE=Release
cmake --build build
```
Headless render needs a GL context: `xvfb-run -a ./build/pcv-render-offscreen out.png`
(or run interactively under the AurumOS/Hyprland session).

## Semantic segmentation (object classes)

Beyond defect colouring, each point can carry a semantic class (Ground,
Sidewalk, Building, Vegetation, Car, Pole). `generate_city_scene()` produces a
labelled street scene and `pcv-render-offscreen <out.png> city` renders it
coloured by class with a per-class point histogram. This demonstrates the
viewer + the semantic data flow — NOT a trained model. A real deployment would
feed labels from a segmentation network (KPConv / RandLA-Net / PTv3, trained on
SemanticKITTI-style data, served via TensorRT); the viewer consumes whatever
labels the model emits.

## In-app model training (computer vision)

`training/` is a real, runnable point-cloud semantic-segmentation trainer:
`cv_train.py` builds labelled street scenes, extracts geometric features, trains
a PyTorch MLP, and evaluates on a HELD-OUT scene (different seed), reporting real
accuracy + per-class IoU and writing the predicted scene as a PLY the viewer
renders. Run: `python3 training/cv_train.py` (or the `aurum-cv-train` launcher).

Verified run (CPU, 60 epochs, ~10s) on a REALISTIC mini case — the dense scene
is turned into a simulated LiDAR scan (occlusion shadows, density falloff with
range, 3 cm sensor noise), confusers are added (low hedges that resemble cars,
garden walls that resemble buildings), 3% label noise is injected into training,
and the test scene has a DIFFERENT layout: 98.6% overall / 92.3% mean IoU, with
poles the hard class at 72% (thin + rare, exactly as in real data). The trainer
also writes a confusion matrix and an error map (misclassified points in red).

IMPORTANT — read before quoting those numbers: the scenes are SYNTHETIC and
clean, and train/test come from the same generator, so accuracy is far higher
than real scanner data would give (real point-cloud segmentation is typically
60-85% mIoU). This proves the *training pipeline and the in-app flow*
(features -> model -> evaluation -> rendered predictions), NOT production
accuracy. The architecture swaps the MLP for a GPU deep net (PointNet/KPConv/
PTv3) and the synthetic scenes for real labelled scans when those exist.

## Status
PROTOTYPE. Verified: compiles, 4 unit tests pass, renders 360k synthetic points
headless. NOT yet done: ingest of real scanner formats (LAS/E57), GPU-accelerated
defect detection, tiling for city-scale clouds. See the architecture note.
