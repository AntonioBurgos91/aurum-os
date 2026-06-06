// render_offscreen — headless proof that the native viewer renders. Generates
// a scene (road-defect or semantic city) or loads a PLY, renders it to an
// off-screen framebuffer, and writes a PNG. For CI / servers with no display.
// Usage: render_offscreen <out.png> [road|city|<in.ply>]
#include <QGuiApplication>
#include <QImage>
#include <QMatrix4x4>
#include <QOffscreenSurface>
#include <QOpenGLContext>
#include <QOpenGLFramebufferObject>
#include <QSurfaceFormat>
#include <cstdio>

#include "gl_renderer.h"
#include "point_cloud.h"

using namespace aurum::pcv;

int main(int argc, char *argv[]) {
  QGuiApplication app(argc, argv);
  const QString out = argc > 1 ? argv[1] : "pointcloud.png";

  PointCloud pc;
  GLRenderer::ColorMode mode = GLRenderer::ColorMode::Defect;
  const QString arg =
      argc > 2 ? QString::fromUtf8(argv[2]) : QStringLiteral("road");
  if (arg == "road") {
    pc = generate_road_scan();
    mode = GLRenderer::ColorMode::Defect;
  } else if (arg == "city") {
    pc = generate_city_scene();
    mode = GLRenderer::ColorMode::Class;
  } else {
    if (!load_ply(pc, argv[2])) {
      std::fprintf(stderr, "failed to load %s\n", argv[2]);
      return 2;
    }
    mode = GLRenderer::ColorMode::Class;
  }
  // If the cloud carries no semantic labels (e.g. an error map), fall back to
  // defect colouring so it renders meaningfully instead of all-grey.
  bool anyLabel = false;
  for (uint8_t l : pc.label)
    if (l > 0) {
      anyLabel = true;
      break;
    }
  if (!anyLabel)
    mode = GLRenderer::ColorMode::Defect;
  std::fprintf(stderr, "points: %zu\n", pc.size());
  if (!pc.label.empty()) {
    const auto h = class_histogram(pc);
    for (std::size_t i = 1; i < h.size(); ++i)
      std::fprintf(stderr, "  %-14s %zu\n",
                   sem_class_name(static_cast<SemClass>(i)), h[i]);
  }

  QSurfaceFormat fmt;
  fmt.setRenderableType(QSurfaceFormat::OpenGL);
  fmt.setVersion(3, 3);
  fmt.setProfile(QSurfaceFormat::CoreProfile);
  fmt.setDepthBufferSize(24);

  QOffscreenSurface surface;
  surface.setFormat(fmt);
  surface.create();
  if (!surface.isValid()) {
    std::fprintf(stderr, "offscreen surface invalid\n");
    return 3;
  }
  QOpenGLContext ctx;
  ctx.setFormat(fmt);
  if (!ctx.create() || !ctx.makeCurrent(&surface)) {
    std::fprintf(stderr, "no GL context (need EGL/OSMesa)\n");
    return 4;
  }

  const int W = 1400, H = 900;
  QOpenGLFramebufferObject fbo(W, H, QOpenGLFramebufferObject::Depth);
  fbo.bind();

  GLRenderer r;
  r.init();
  r.upload(pc, mode);
  const Bounds b = r.bounds();

  QMatrix4x4 proj;
  proj.perspective(45.0f, static_cast<float>(W) / H, 0.05f, 1000.0f);
  QMatrix4x4 view;
  const float dist = b.radius * 1.15f;
  // Lower, three-quarter angle: potholes read as depressions, a city scene
  // reads as a street receding into the distance.
  view.lookAt(
      QVector3D(b.center[0] - dist * 0.7f, b.center[1] - dist * 0.9f,
                b.center[2] + dist * 0.35f),
      QVector3D(b.center[0], b.center[1], b.center[2] - b.radius * 0.05f),
      QVector3D(0, 0, 1));
  r.render(proj * view, W, H, 2.5f);

  ctx.functions()->glFinish();
  const QImage img = fbo.toImage();
  fbo.release();
  if (!img.save(out)) {
    std::fprintf(stderr, "failed to save %s\n", out.toUtf8().constData());
    return 5;
  }
  std::fprintf(stderr, "wrote %s (%dx%d)\n", out.toUtf8().constData(), W, H);
  return 0;
}
