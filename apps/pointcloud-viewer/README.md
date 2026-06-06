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

## Status
PROTOTYPE. Verified: compiles, 4 unit tests pass, renders 360k synthetic points
headless. NOT yet done: ingest of real scanner formats (LAS/E57), GPU-accelerated
defect detection, tiling for city-scale clouds. See the architecture note.
