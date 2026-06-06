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

## Status
PROTOTYPE. Verified: compiles, 4 unit tests pass, renders 360k synthetic points
headless. NOT yet done: ingest of real scanner formats (LAS/E57), GPU-accelerated
defect detection, tiling for city-scale clouds. See the architecture note.
