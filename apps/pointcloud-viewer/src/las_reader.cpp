#include "las_reader.h"

#include <cstring>
#include <fstream>
#include <vector>

#include "point_cloud.h"

namespace aurum::pcv {

namespace {
// Little-endian readers (LAS is little-endian; x86/ARM64 targets match, but we
// read via memcpy from a byte buffer to stay alignment- and aliasing-safe).
template <typename T>
T rd(const uint8_t* p) {
    T v;
    std::memcpy(&v, p, sizeof(T));
    return v;
}

struct LasHeader {
    uint8_t version_major = 0, version_minor = 0;
    uint16_t header_size = 0;
    uint32_t point_offset = 0;
    uint8_t point_format = 0;
    uint16_t point_record_len = 0;
    uint64_t point_count = 0;
    double scale[3]{}, offset[3]{};
};

bool parse_header(std::ifstream& f, LasHeader& h, std::string* err) {
    // LAS 1.4 header is 375 bytes; 1.2's is 227. Read the max and index fields
    // by offset per the ASPRS spec (fields below are stable across 1.2-1.4).
    std::vector<uint8_t> buf(375, 0);
    f.read(reinterpret_cast<char*>(buf.data()), 375);
    const auto got = static_cast<size_t>(f.gcount());
    if (got < 227) {
        if (err) *err = "file too small for a LAS header";
        return false;
    }
    if (std::memcmp(buf.data(), "LASF", 4) != 0) {
        if (err) *err = "bad magic (not a LAS file)";
        return false;
    }
    h.version_major = buf[24];
    h.version_minor = buf[25];
    h.header_size = rd<uint16_t>(&buf[94]);
    h.point_offset = rd<uint32_t>(&buf[96]);
    h.point_format = buf[104] & 0x3F;  // top bits flag internal LAZ compression
    h.point_record_len = rd<uint16_t>(&buf[105]);
    const uint32_t legacy_count = rd<uint32_t>(&buf[107]);
    for (int k = 0; k < 3; ++k) {
        h.scale[k] = rd<double>(&buf[131 + 8 * k]);
        h.offset[k] = rd<double>(&buf[155 + 8 * k]);
    }
    h.point_count = legacy_count;
    // LAS 1.4: 64-bit count lives at offset 247; legacy field may be 0.
    if (h.version_major == 1 && h.version_minor >= 4 && got >= 255) {
        const uint64_t c64 = rd<uint64_t>(&buf[247]);
        if (c64 > 0) h.point_count = c64;
    }
    if (buf[104] & 0xC0) {
        if (err) *err = "LAZ-compressed LAS is not supported (decompress first, or use PDAL)";
        return false;
    }
    if (h.version_major != 1 || h.version_minor > 4) {
        if (err) *err = "unsupported LAS version";
        return false;
    }
    if (h.point_format > 8) {
        if (err) *err = "unsupported point data record format";
        return false;
    }
    return true;
}
}  // namespace

uint8_t asprs_to_semclass(uint8_t asprs) {
    switch (asprs) {
        case 2:   // Ground
        case 11:  // Road surface
            return static_cast<uint8_t>(SemClass::Ground);
        case 3:
        case 4:
        case 5:  // Low/Medium/High vegetation
            return static_cast<uint8_t>(SemClass::Vegetation);
        case 6:  // Building
            return static_cast<uint8_t>(SemClass::Building);
        default:
            return static_cast<uint8_t>(SemClass::Unlabeled);
    }
}

bool load_las(PointCloud& pc, const std::string& path, std::string* error) {
    std::ifstream f(path, std::ios::binary);
    if (!f) {
        if (error) *error = "cannot open file";
        return false;
    }
    LasHeader h;
    if (!parse_header(f, h, error)) return false;

    // Classification byte position within a point record, by format:
    //   formats 0-5: byte 15;  formats 6-8 (LAS 1.4): byte 16.
    const size_t cls_at = (h.point_format >= 6) ? 16 : 15;
    if (h.point_record_len < cls_at + 1 || h.point_record_len < 12) {
        if (error) *error = "point record too short for declared format";
        return false;
    }

    // The header read requests 375 bytes; a small LAS 1.2 file can be shorter,
    // leaving eof/fail set on the stream — clear before seeking or seekg fails.
    f.clear();
    f.seekg(h.point_offset, std::ios::beg);
    if (!f) {
        if (error) *error = "point data offset beyond file";
        return false;
    }

    pc.clear();
    pc.reserve(static_cast<size_t>(h.point_count));
    std::vector<uint8_t> rec(h.point_record_len);
    for (uint64_t i = 0; i < h.point_count; ++i) {
        f.read(reinterpret_cast<char*>(rec.data()), h.point_record_len);
        if (static_cast<size_t>(f.gcount()) < h.point_record_len) {
            if (error) *error = "truncated point data";
            return false;
        }
        const double x = rd<int32_t>(&rec[0]) * h.scale[0] + h.offset[0];
        const double y = rd<int32_t>(&rec[4]) * h.scale[1] + h.offset[1];
        const double z = rd<int32_t>(&rec[8]) * h.scale[2] + h.offset[2];
        // Formats 0-5 pack class in the low 5 bits (upper 3 are flags); 6-8 use
        // the whole byte.
        uint8_t cls = rec[cls_at];
        if (h.point_format < 6) cls &= 0x1F;
        pc.push(static_cast<float>(x), static_cast<float>(y), static_cast<float>(z), 0.0f,
                static_cast<SemClass>(asprs_to_semclass(cls)));
    }
    return true;
}

}  // namespace aurum::pcv
