// Pure-logic tests: bounds, defect colour mapping, PLY round-trip, and that the
// synthetic scan actually produces defect points (so the demo isn't empty).
#include <QtTest>

#include "point_cloud.h"

using namespace aurum::pcv;

class TestPointCloud : public QObject {
  Q_OBJECT
private slots:
  void bounds_center_and_radius();
  void defect_color_ramp();
  void ply_round_trip();
  void road_scan_has_defects();
};

void TestPointCloud::bounds_center_and_radius() {
  PointCloud pc;
  pc.push(-1, -1, -1, 0);
  pc.push(1, 1, 1, 0);
  const Bounds b = compute_bounds(pc);
  QCOMPARE(b.center[0], 0.0f);
  QCOMPARE(b.center[1], 0.0f);
  QCOMPARE(b.center[2], 0.0f);
  QVERIFY(b.radius > 1.7f && b.radius < 1.74f); // sqrt(3)
}

void TestPointCloud::defect_color_ramp() {
  float r, g, b;
  defect_color(0.0f, r, g, b);
  QVERIFY(r < 0.01f && g > 0.99f); // healthy = green
  defect_color(0.5f, r, g, b);
  QVERIFY(r > 0.99f && g > 0.99f); // mid = yellow
  defect_color(1.0f, r, g, b);
  QVERIFY(r > 0.99f && g < 0.01f); // severe = red
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
    if (d > 0.5f)
      ++defectPoints;
  QVERIFY2(defectPoints > 50,
           "synthetic scan should contain clear defect points");
}

QTEST_GUILESS_MAIN(TestPointCloud)
#include "test_point_cloud.moc"
