#pragma once
#include <cstdint>
#include <string>
#include <vector>

namespace aurum::pcv {

// A point cloud as the road-scanning pipeline would produce it: XYZ geometry
// plus a per-point defect score in [0,1] (0 = healthy asphalt, 1 = severe
// pothole/crack). Stored as flat float arrays so it maps straight onto a GPU
// vertex buffer with no per-point object overhead — this is what keeps a
// multi-million-point cloud interactive.
struct PointCloud {
  std::vector<float> xyz;    // size = 3 * count
  std::vector<float> defect; // size = count, in [0,1]

  std::size_t size() const { return defect.size(); }
  void clear() {
    xyz.clear();
    defect.clear();
  }
  void reserve(std::size_t n) {
    xyz.reserve(3 * n);
    defect.reserve(n);
  }
  void push(float x, float y, float z, float d) {
    xyz.push_back(x);
    xyz.push_back(y);
    xyz.push_back(z);
    defect.push_back(d);
  }
};

// Axis-aligned bounds, for fitting the camera.
struct Bounds {
  float min[3]{0, 0, 0};
  float max[3]{0, 0, 0};
  float center[3]{0, 0, 0};
  float radius{1.0f};
};
Bounds compute_bounds(const PointCloud &pc);

// Map a defect score to an RGB colour (green -> yellow -> red), the way the
// viewer shades points. Pure + unit-testable.
void defect_color(float score, float &r, float &g, float &b);

// Minimal ASCII PLY load/save (x y z [defect]). Enough to round-trip the
// pipeline's output and to load real scans. Returns false on parse error.
bool save_ply(const PointCloud &pc, const std::string &path);
bool load_ply(PointCloud &pc, const std::string &path);

// Synthetic street scan for the demo: a flat asphalt strip with a few potholes
// (bowl depressions) and cracks (thin linear depressions), with defect scores
// derived from local depth deviation — i.e. the same signal a real detector
// keys on. Deterministic given the seed so screenshots are reproducible.
PointCloud generate_road_scan(int length_m = 40, int width_m = 6,
                              float density_per_m2 = 1500.0f,
                              uint32_t seed = 42);

} // namespace aurum::pcv
