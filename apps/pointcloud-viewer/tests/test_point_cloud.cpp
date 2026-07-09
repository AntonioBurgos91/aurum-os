// Pure-logic tests: bounds, defect colour mapping, PLY round-trip, and that the
// synthetic scan actually produces defect points (so the demo isn't empty).
#include <QtTest>
#include <array>

#include "las_reader.h"
#include "point_cloud.h"

using namespace aurum::pcv;

class TestPointCloud : public QObject {
    Q_OBJECT
private slots:
    void bounds_center_and_radius();
    void defect_color_ramp();
    void ply_round_trip();
    void road_scan_has_defects();
    void class_colors_are_distinct();
    void class_histogram_counts();
    void city_scene_has_all_classes();
    void las_round_trip();
};

void TestPointCloud::bounds_center_and_radius() {
    PointCloud pc;
    pc.push(-1, -1, -1, 0);
    pc.push(1, 1, 1, 0);
    const Bounds b = compute_bounds(pc);
    QCOMPARE(b.center[0], 0.0f);
    QCOMPARE(b.center[1], 0.0f);
    QCOMPARE(b.center[2], 0.0f);
    QVERIFY(b.radius > 1.7f && b.radius < 1.74f);  // sqrt(3)
}

void TestPointCloud::defect_color_ramp() {
    float r, g, b;
    defect_color(0.0f, r, g, b);
    QVERIFY(r < 0.01f && g > 0.99f);  // healthy = green
    defect_color(0.5f, r, g, b);
    QVERIFY(r > 0.99f && g > 0.99f);  // mid = yellow
    defect_color(1.0f, r, g, b);
    QVERIFY(r > 0.99f && g < 0.01f);  // severe = red
    // Clamped.
    defect_color(5.0f, r, g, b);
    QVERIFY(r > 0.99f && g < 0.01f);
}

void TestPointCloud::ply_round_trip() {
    PointCloud a;
    a.push(1.5f, 2.5f, 3.5f, 0.7f);
    a.push(-4.0f, 0.0f, 9.0f, 0.2f);
    const QString tmp = QDir::tempPath() + "/pcv_test.ply";
    QVERIFY(save_ply(a, tmp.toStdString()));
    PointCloud b;
    QVERIFY(load_ply(b, tmp.toStdString()));
    QCOMPARE(b.size(), a.size());
    QCOMPARE(b.xyz[0], 1.5f);
    QCOMPARE(b.xyz[5], 9.0f);
    QVERIFY(qAbs(b.defect[0] - 0.7f) < 1e-4f);
}

void TestPointCloud::road_scan_has_defects() {
    const PointCloud pc = generate_road_scan(20, 5, 800.0f, 7);
    QVERIFY(pc.size() > 1000);
    int defectPoints = 0;
    for (float d : pc.defect)
        if (d > 0.5f) ++defectPoints;
    QVERIFY2(defectPoints > 50, "synthetic scan should contain clear defect points");
}

void TestPointCloud::class_colors_are_distinct() {
    std::vector<std::array<float, 3>> seen;
    for (int i = 1; i < int(SemClass::Count); ++i) {
        float r, g, b;
        class_color(static_cast<SemClass>(i), r, g, b);
        for (auto &c : seen)
            QVERIFY2(!(qFuzzyCompare(c[0], r) && qFuzzyCompare(c[1], g) && qFuzzyCompare(c[2], b)),
                     "two classes share a colour");
        seen.push_back({r, g, b});
    }
}

void TestPointCloud::class_histogram_counts() {
    PointCloud pc;
    pc.push(0, 0, 0, 0, SemClass::Car);
    pc.push(1, 0, 0, 0, SemClass::Car);
    pc.push(2, 0, 0, 0, SemClass::Building);
    const auto h = class_histogram(pc);
    QCOMPARE(h[std::size_t(SemClass::Car)], std::size_t(2));
    QCOMPARE(h[std::size_t(SemClass::Building)], std::size_t(1));
    QCOMPARE(h[std::size_t(SemClass::Vegetation)], std::size_t(0));
}

void TestPointCloud::city_scene_has_all_classes() {
    const PointCloud pc = generate_city_scene(40, 16, 3);
    QVERIFY(pc.size() > 10000);
    QCOMPARE(pc.label.size(), pc.size());
    const auto h = class_histogram(pc);
    for (auto c : {SemClass::Ground, SemClass::Sidewalk, SemClass::Building, SemClass::Vegetation,
                   SemClass::Car, SemClass::Pole})
        QVERIFY2(h[std::size_t(c)] > 0, sem_class_name(c));
}

void TestPointCloud::las_round_trip() {
    // Hand-craft a minimal LAS 1.2 / point-format-0 file (227-byte header + two
    // 20-byte records; scale 0.001) and load it through the real reader.
    const QString path = QDir::tempPath() + "/pcv_test.las";
    QByteArray h(227, '\0');
    memcpy(h.data(), "LASF", 4);
    h[24] = 1;
    h[25] = 2;  // version 1.2
    auto put16 = [&](int at, quint16 v) { memcpy(h.data() + at, &v, 2); };
    auto put32 = [&](int at, quint32 v) { memcpy(h.data() + at, &v, 4); };
    auto putD = [&](int at, double v) { memcpy(h.data() + at, &v, 8); };
    put16(94, 227);  // header size
    put32(96, 227);  // offset to point data
    h[104] = 0;      // point format 0
    put16(105, 20);  // record length
    put32(107, 2);   // legacy point count
    for (int k = 0; k < 3; ++k) {
        putD(131 + 8 * k, 0.001);  // scale
        putD(155 + 8 * k, 0.0);    // offset
    }
    QByteArray recs(40, '\0');
    auto putPt = [&](int base, qint32 x, qint32 y, qint32 z, quint8 cls) {
        memcpy(recs.data() + base + 0, &x, 4);
        memcpy(recs.data() + base + 4, &y, 4);
        memcpy(recs.data() + base + 8, &z, 4);
        recs[base + 15] = static_cast<char>(cls);
    };
    putPt(0, 1500, 2500, 3500, 2);  // (1.5,2.5,3.5) ASPRS Ground
    putPt(20, -4000, 0, 8000, 6);   // (-4,0,8)     ASPRS Building
    QFile f(path);
    QVERIFY(f.open(QIODevice::WriteOnly | QIODevice::Truncate));
    f.write(h);
    f.write(recs);
    f.close();

    PointCloud pc;
    std::string err;
    QVERIFY2(load_las(pc, path.toStdString(), &err), err.c_str());
    QCOMPARE(pc.size(), std::size_t(2));
    QVERIFY(qAbs(pc.xyz[0] - 1.5f) < 1e-3f);
    QCOMPARE(pc.label[0], quint8(SemClass::Ground));
    QCOMPARE(pc.label[1], quint8(SemClass::Building));

    // Garbage must fail with an error, never crash.
    const QString bad = QDir::tempPath() + "/pcv_bad.las";
    QFile fb(bad);
    QVERIFY(fb.open(QIODevice::WriteOnly | QIODevice::Truncate));
    fb.write(QByteArray(300, 'X'));
    fb.close();
    PointCloud pc2;
    QVERIFY(!load_las(pc2, bad.toStdString(), &err));
    QVERIFY(!err.empty());

    // Pure ASPRS mapping.
    QCOMPARE(asprs_to_semclass(11), quint8(SemClass::Ground));  // road surface
    QCOMPARE(asprs_to_semclass(4), quint8(SemClass::Vegetation));
    QCOMPARE(asprs_to_semclass(99), quint8(SemClass::Unlabeled));
}

QTEST_GUILESS_MAIN(TestPointCloud)
#include "test_point_cloud.moc"
