#pragma once
// Minimal LAS reader (LAS 1.2 - 1.4) for the point-cloud viewer.
//
// Scope (deliberate): XYZ via scale/offset, plus the per-point Classification
// byte, for point data record formats 0-8 — enough to load the road scans the
// company's scanners produce and colour them by ASPRS class. Compressed LAZ,
// waveform data, VLR parsing and full attribute decoding are out of scope; a
// production ingest would sit on PDAL. This is dependency-free on purpose so
// it compiles anywhere pcv-core does (and is unit-testable without Qt).
//
// Reference: ASPRS LAS 1.4 specification (point formats 6-8 move the
// classification byte and widen the record; both layouts are handled).
#include <cstdint>
#include <string>

namespace aurum::pcv {

struct PointCloud;  // point_cloud.h

// ASPRS standard classification codes → our SemClass (viewer palette).
//   2 Ground → Ground, 3/4/5 Low/Med/High vegetation → Vegetation,
//   6 Building → Building, 9 Water → Unlabeled, 11 Road surface → Ground,
//   others → Unlabeled. Pure + unit-tested.
uint8_t asprs_to_semclass(uint8_t asprs);

// Load a .las file (uncompressed). Returns false and fills `error` on any
// structural problem (bad magic, unsupported version/format, truncated file).
// On success fills `pc` (defect=0; label from Classification via
// asprs_to_semclass).
bool load_las(PointCloud& pc, const std::string& path, std::string* error = nullptr);

}  // namespace aurum::pcv
