#include "point_cloud.h"

#include <algorithm>
#include <cmath>
#include <fstream>
#include <random>
#include <sstream>
#include <vector>

namespace aurum::pcv {

Bounds compute_bounds(const PointCloud &pc) {
  Bounds b;
  if (pc.size() == 0)
    return b;
  for (int k = 0; k < 3; ++k) {
    b.min[k] = b.max[k] = pc.xyz[k];
  }
  for (std::size_t i = 0; i < pc.size(); ++i) {
    for (int k = 0; k < 3; ++k) {
      const float v = pc.xyz[3 * i + k];
      b.min[k] = std::min(b.min[k], v);
      b.max[k] = std::max(b.max[k], v);
    }
  }
  float r2 = 0.0f;
  for (int k = 0; k < 3; ++k) {
    b.center[k] = 0.5f * (b.min[k] + b.max[k]);
    const float half = 0.5f * (b.max[k] - b.min[k]);
    r2 += half * half;
  }
  b.radius = std::sqrt(r2);
  if (b.radius < 1e-3f)
    b.radius = 1.0f;
  return b;
}

void defect_color(float score, float &r, float &g, float &b) {
  // Clamp, then green(0) -> yellow(0.5) -> red(1.0).
  score = std::clamp(score, 0.0f, 1.0f);
  if (score < 0.5f) {
    const float t = score / 0.5f; // 0..1 over green->yellow
    r = t;
    g = 1.0f;
    b = 0.0f;
  } else {
    const float t = (score - 0.5f) / 0.5f; // 0..1 over yellow->red
    r = 1.0f;
    g = 1.0f - t;
    b = 0.0f;
  }
}

bool save_ply(const PointCloud &pc, const std::string &path) {
  std::ofstream f(path);
  if (!f)
    return false;
  f << "ply\nformat ascii 1.0\n";
  f << "element vertex " << pc.size() << "\n";
  f << "property float x\nproperty float y\nproperty float z\n";
  f << "property float defect\n";
  f << "end_header\n";
  for (std::size_t i = 0; i < pc.size(); ++i) {
    f << pc.xyz[3 * i] << " " << pc.xyz[3 * i + 1] << " " << pc.xyz[3 * i + 2]
      << " " << pc.defect[i] << "\n";
  }
  return static_cast<bool>(f);
}

bool load_ply(PointCloud &pc, const std::string &path) {
  std::ifstream f(path);
  if (!f)
    return false;
  std::string line;
  std::size_t count = 0;
  // Track property order so we can read x,y,z plus optional defect/label in any
  // column position (the trainer writes "x y z defect label").
  int prop_index = 0, defect_at = -1, label_at = -1, n_props = 0;
  while (std::getline(f, line)) {
    std::istringstream ls(line);
    std::string tok;
    ls >> tok;
    if (tok == "element") {
      std::string what;
      ls >> what >> count;
    } else if (tok == "property") {
      std::string type, name;
      ls >> type >> name;
      if (name == "defect")
        defect_at = prop_index;
      else if (name == "label")
        label_at = prop_index;
      ++prop_index;
      ++n_props;
    } else if (tok == "end_header") {
      break;
    }
  }
  pc.clear();
  pc.reserve(count);
  for (std::size_t i = 0; i < count && std::getline(f, line); ++i) {
    std::istringstream ls(line);
    // Read every column of the row into a buffer, then pick out what we need.
    std::vector<float> col;
    col.reserve(n_props);
    float v;
    while (ls >> v)
      col.push_back(v);
    if (col.size() < 3)
      continue;
    const float x = col[0], y = col[1], z = col[2];
    const float d =
        (defect_at >= 0 && defect_at < (int)col.size()) ? col[defect_at] : 0.0f;
    SemClass cls = SemClass::Unlabeled;
    if (label_at >= 0 && label_at < (int)col.size()) {
      const int li = static_cast<int>(col[label_at]);
      if (li > 0 && li < static_cast<int>(SemClass::Count))
        cls = static_cast<SemClass>(li);
    }
    pc.push(x, y, z, d, cls);
  }
  return true;
}

PointCloud generate_road_scan(int length_m, int width_m, float density_per_m2,
                              uint32_t seed) {
  PointCloud pc;
  std::mt19937 rng(seed);
  std::uniform_real_distribution<float> ux(0.0f, static_cast<float>(length_m));
  std::uniform_real_distribution<float> uy(-width_m * 0.5f, width_m * 0.5f);
  std::normal_distribution<float> surf_noise(0.0f,
                                             0.004f); // 4mm asphalt roughness

  // A few potholes (cx, cy, radius, depth) and cracks (x0,y0,x1,y1,depth).
  struct Pot {
    float cx, cy, r, depth;
  };
  struct Crack {
    float x0, y0, x1, y1, depth;
  };
  const Pot pots[] = {
      {8.0f, -1.2f, 0.55f, 0.09f},
      {22.0f, 1.0f, 0.8f, 0.14f},
      {31.0f, -0.4f, 0.4f, 0.06f},
  };
  const Crack cracks[] = {
      {3.0f, 2.0f, 14.0f, -2.2f, 0.05f},
      {18.0f, -2.5f, 27.0f, 2.4f, 0.04f},
      {25.0f, 0.0f, 38.0f, 0.8f, 0.06f},
  };

  const auto total =
      static_cast<std::size_t>(length_m * width_m * density_per_m2);
  pc.reserve(total);

  for (std::size_t i = 0; i < total; ++i) {
    const float x = ux(rng);
    const float y = uy(rng);
    float z = surf_noise(rng); // base asphalt height
    float defect = 0.0f;

    // Potholes: gaussian bowls.
    for (const auto &p : pots) {
      const float dx = x - p.cx, dy = y - p.cy;
      const float d2 = dx * dx + dy * dy;
      const float infl = std::exp(-d2 / (2.0f * p.r * p.r));
      z -= p.depth * infl;
      defect = std::max(defect, infl * std::clamp(p.depth / 0.12f, 0.0f, 1.0f));
    }
    // Cracks: distance to a segment, thin influence.
    for (const auto &c : cracks) {
      const float vx = c.x1 - c.x0, vy = c.y1 - c.y0;
      const float wx = x - c.x0, wy = y - c.y0;
      const float len2 = vx * vx + vy * vy;
      float t = len2 > 0 ? (wx * vx + wy * vy) / len2 : 0.0f;
      t = std::clamp(t, 0.0f, 1.0f);
      const float px = c.x0 + t * vx, py = c.y0 + t * vy;
      const float dd = std::hypot(x - px, y - py);
      const float infl =
          std::exp(-(dd * dd) / (2.0f * 0.05f * 0.05f)); // ~5cm wide
      z -= c.depth * infl;
      defect = std::max(defect, infl * 0.85f);
    }
    pc.push(x, y, z, defect);
  }
  return pc;
}

// ── Semantic class helpers ──────────────────────────────────────────────────

const char *sem_class_name(SemClass c) {
  switch (c) {
  case SemClass::Ground:
    return "Suelo";
  case SemClass::Sidewalk:
    return "Acera";
  case SemClass::Building:
    return "Edificio";
  case SemClass::Vegetation:
    return "Vegetacion";
  case SemClass::Car:
    return "Coche";
  case SemClass::Pole:
    return "Poste";
  case SemClass::Unlabeled:
  default:
    return "Sin clasificar";
  }
}

void class_color(SemClass c, float &r, float &g, float &b) {
  // A distinct, readable palette (SemanticKITTI-ish).
  switch (c) {
  case SemClass::Ground:
    r = 0.40f;
    g = 0.40f;
    b = 0.45f;
    break; // grey asphalt
  case SemClass::Sidewalk:
    r = 0.65f;
    g = 0.62f;
    b = 0.55f;
    break; // tan
  case SemClass::Building:
    r = 0.90f;
    g = 0.55f;
    b = 0.25f;
    break; // orange
  case SemClass::Vegetation:
    r = 0.20f;
    g = 0.75f;
    b = 0.30f;
    break; // green
  case SemClass::Car:
    r = 0.20f;
    g = 0.55f;
    b = 0.95f;
    break; // blue
  case SemClass::Pole:
    r = 0.95f;
    g = 0.85f;
    b = 0.20f;
    break; // yellow
  case SemClass::Unlabeled:
  default:
    r = 0.30f;
    g = 0.30f;
    b = 0.32f;
    break;
  }
}

std::vector<std::size_t> class_histogram(const PointCloud &pc) {
  std::vector<std::size_t> h(static_cast<std::size_t>(SemClass::Count), 0);
  for (uint8_t l : pc.label) {
    if (l < h.size())
      ++h[l];
  }
  return h;
}

PointCloud generate_city_scene(int length_m, int width_m, uint32_t seed) {
  PointCloud pc;
  std::mt19937 rng(seed);
  std::uniform_real_distribution<float> u01(0.0f, 1.0f);
  std::normal_distribution<float> jitter(0.0f, 0.01f);

  const float halfW = width_m * 0.5f;
  const float roadHalf = 4.0f; // 8m carriageway
  const float walkW = 2.0f;    // sidewalk width each side

  auto rx = [&]() { return u01(rng) * length_m; };

  // 1. Ground (road) + sidewalks: dense flat sampling.
  const int groundPts = length_m * width_m * 120;
  for (int i = 0; i < groundPts; ++i) {
    const float x = rx();
    const float y = (u01(rng) * 2.0f - 1.0f) * halfW;
    const float z = jitter(rng);
    const float ay = std::fabs(y);
    SemClass cls;
    float zz = z;
    if (ay <= roadHalf) {
      cls = SemClass::Ground;
    } else if (ay <= roadHalf + walkW) {
      cls = SemClass::Sidewalk;
      zz = z + 0.12f; // kerb step up
    } else {
      continue; // beyond sidewalk handled by buildings below
    }
    pc.push(x, y, zz, 0.0f, cls);
  }

  // 2. Buildings: facades along both sides beyond the sidewalk.
  const float facadeY = roadHalf + walkW;
  for (int side = -1; side <= 1; side += 2) {
    float x = 0.0f;
    while (x < length_m) {
      const float bw = 6.0f + u01(rng) * 8.0f;  // building width along street
      const float bh = 6.0f + u01(rng) * 14.0f; // height
      const float depth = 0.4f;                 // facade thickness sampled
      const int n = static_cast<int>(bw * bh * 40);
      for (int i = 0; i < n; ++i) {
        const float bx = x + u01(rng) * bw;
        const float by = side * (facadeY + u01(rng) * depth);
        const float bz = u01(rng) * bh;
        pc.push(bx, by, bz, 0.0f, SemClass::Building);
      }
      x += bw + (0.5f + u01(rng) * 1.5f); // gap between buildings
    }
  }

  // 3. Parked cars along the kerb (boxes), both sides.
  struct Box {
    float cx, cy, L, W, H;
  };
  for (int side = -1; side <= 1; side += 2) {
    float x = 5.0f;
    while (x < length_m - 5.0f) {
      if (u01(rng) < 0.6f) {
        const float L = 4.2f, W = 1.8f, H = 1.45f;
        const float cy = side * (roadHalf - 1.0f);
        const int n = 2500;
        for (int i = 0; i < n; ++i) {
          const float lx = x + u01(rng) * L;
          const float ly = cy + (u01(rng) - 0.5f) * W;
          const float lz = 0.2f + u01(rng) * H;
          pc.push(lx, ly, lz, 0.0f, SemClass::Car);
        }
      }
      x += 6.0f + u01(rng) * 4.0f;
    }
  }

  // 4. Street trees (sphere canopy + trunk) on the sidewalk.
  for (int side = -1; side <= 1; side += 2) {
    for (float x = 8.0f; x < length_m; x += 12.0f + u01(rng) * 6.0f) {
      const float ty = side * (roadHalf + walkW * 0.5f);
      // trunk
      for (int i = 0; i < 300; ++i)
        pc.push(x + jitter(rng), ty + jitter(rng), u01(rng) * 2.2f, 0.0f,
                SemClass::Vegetation);
      // canopy
      const float cz = 3.0f, cr = 1.6f;
      for (int i = 0; i < 2500; ++i) {
        const float a = u01(rng) * 6.2832f, e = (u01(rng) - 0.5f) * 3.14159f,
                    rr = cr * std::cbrt(u01(rng));
        pc.push(x + rr * std::cos(a) * std::cos(e),
                ty + rr * std::sin(a) * std::cos(e), cz + rr * std::sin(e),
                0.0f, SemClass::Vegetation);
      }
    }
  }

  // 5. Lamp posts on the sidewalk.
  for (int side = -1; side <= 1; side += 2) {
    for (float x = 14.0f; x < length_m; x += 18.0f) {
      const float py = side * (roadHalf + walkW * 0.8f);
      for (int i = 0; i < 400; ++i)
        pc.push(x + jitter(rng), py + jitter(rng), u01(rng) * 5.0f, 0.0f,
                SemClass::Pole);
    }
  }

  return pc;
}

} // namespace aurum::pcv
