// aurum-pointcloud-viewer — native interactive 3D point-cloud viewer for road
// scans. Mouse-drag to orbit, wheel to zoom, keys 1/2/3 to size points. Loads a
// PLY passed on the command line, else shows the synthetic demo scan. Points
// are shaded by defect score (green healthy -> red severe), matching the
// detector.
#include <QApplication>
#include <QKeyEvent>
#include <QMatrix4x4>
#include <QMouseEvent>
#include <QOpenGLWindow>
#include <QWheelEvent>

#include "gl_renderer.h"
#include "point_cloud.h"

using namespace aurum::pcv;

class ViewerWindow : public QOpenGLWindow {
public:
  explicit ViewerWindow(PointCloud pc) : m_pc(std::move(pc)) {}

protected:
  void initializeGL() override {
    m_r.init();
    m_r.upload(m_pc);
    m_b = m_r.bounds();
    m_dist = m_b.radius * 1.6f;
  }
  void resizeGL(int w, int h) override {
    m_w = w;
    m_h = h;
  }
  void paintGL() override {
    QMatrix4x4 proj;
    proj.perspective(45.0f, m_h ? float(m_w) / m_h : 1.0f, 0.05f, 1000.0f);
    QMatrix4x4 view;
    const float cy = std::cos(m_yaw), sy = std::sin(m_yaw);
    const float cp = std::cos(m_pitch), sp = std::sin(m_pitch);
    const QVector3D eye(m_b.center[0] + m_dist * cp * sy,
                        m_b.center[1] - m_dist * cp * cy,
                        m_b.center[2] + m_dist * sp);
    view.lookAt(eye, QVector3D(m_b.center[0], m_b.center[1], m_b.center[2]),
                QVector3D(0, 0, 1));
    m_r.render(proj * view, m_w, m_h, m_pointSize);
  }
  void mousePressEvent(QMouseEvent *e) override { m_last = e->position(); }
  void mouseMoveEvent(QMouseEvent *e) override {
    const QPointF d = e->position() - m_last;
    m_last = e->position();
    m_yaw += float(d.x()) * 0.01f;
    m_pitch = std::clamp(m_pitch + float(d.y()) * 0.01f, -1.5f, 1.5f);
    update();
  }
  void wheelEvent(QWheelEvent *e) override {
    m_dist *= (e->angleDelta().y() > 0) ? 0.9f : 1.1f;
    update();
  }
  void keyPressEvent(QKeyEvent *e) override {
    if (e->key() == Qt::Key_1)
      m_pointSize = 1.5f;
    if (e->key() == Qt::Key_2)
      m_pointSize = 3.0f;
    if (e->key() == Qt::Key_3)
      m_pointSize = 5.0f;
    update();
  }

private:
  PointCloud m_pc;
  GLRenderer m_r;
  Bounds m_b;
  float m_yaw{0.4f}, m_pitch{0.7f}, m_dist{10.0f}, m_pointSize{2.5f};
  int m_w{1400}, m_h{900};
  QPointF m_last;
};

int main(int argc, char *argv[]) {
  QApplication app(argc, argv);
  PointCloud pc;
  if (argc > 1) {
    if (!load_ply(pc, argv[1]))
      pc = generate_road_scan();
  } else {
    pc = generate_road_scan();
  }
  QSurfaceFormat fmt;
  fmt.setVersion(3, 3);
  fmt.setProfile(QSurfaceFormat::CoreProfile);
  fmt.setDepthBufferSize(24);
  QSurfaceFormat::setDefaultFormat(fmt);

  ViewerWindow w(std::move(pc));
  w.setTitle("AurumOS — Point Cloud Viewer");
  w.resize(1400, 900);
  w.show();
  return app.exec();
}
