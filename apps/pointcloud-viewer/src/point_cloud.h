#pragma once
#include <cstdint>
#include <string>
#include <vector>

namespace aurum::pcv {

// Semantic class of a point, as a street-scene segmentation model (KPConv /
// RandLA-Net / PTv3, trained on SemanticKITTI-style data) would assign.
enum class SemClass : uint8_t {
  Unlabeled = 0,
  Ground = 1,
  Sidewalk = 2,
  Building = 3,
  Vegetation = 4,
  Car = 5,
  Pole = 6,
  Count = 7
};
const char *sem_class_name(SemClass c);

// A point cloud as the scanning pipeline would produce it: XYZ geometry, a
// per-point defect score in [0,1], AND a per-point semantic label (SemClass).
// Flat arrays so the whole thing maps onto one GPU vertex buffer.
struct PointCloud {
  std::vector<float> xyz;     // size = 3 * count
  std::vector<float> defect;  // size = count, in [0,1]
  std::vector<uint8_t> label; // size = count, SemClass as uint8

  std::size_t size() const { return defect.size(); }
  void clear() {
    xyz.clear();
    defect.clear();
    label.clear();
  }
  void reserve(std::size_t n) {
    xyz.reserve(3 * n);
    defect.reserve(n);
    label.reserve(n);
  }
  void push(float x, float y, float z, float d) {
    push(x, y, z, d, SemClass::Unlabeled);
  }
  void push(float x, float y, float z, float d, SemClass c) {
    xyz.push_back(x);
    xyz.push_back(y);
    xyz.push_back(z);
    defect.push_back(d);
    label.push_back(static_cast<uint8_t>(c));
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

// Map a semantic class to its display RGB. Pure + unit-testable.
void class_color(SemClass c, float &r, float &g, float &b);

// Count points per semantic class; returns a vector of size SemClass::Count.
std::vector<std::size_t> class_histogram(const PointCloud &pc);

// Synthetic road scan (defect demo): asphalt strip + potholes + cracks.
PointCloud generate_road_scan(int length_m = 40, int width_m = 6,
                              float density_per_m2 = 1500.0f,
                              uint32_t seed = 42);

// Synthetic SEMANTIC street scene: ground + sidewalks, buildings on both sides,
// parked cars, street trees and lamp posts — every point carries a SemClass
// label, as a segmentation model's output would. Proves the viewer's
// "colour by class" + per-class counts, not the model itself.
PointCloud generate_city_scene(int length_m = 60, int width_m = 16,
                               uint32_t seed = 7);

} // namespace aurum::pcv
