// render_offscreen — headless proof that the native viewer renders. Generates
// (or loads) a road scan, renders it to an off-screen framebuffer with an orbit
// camera, and writes a PNG. Used to validate the pipeline in CI / on servers
// with no display. Usage: render_offscreen <out.png> [in.ply]
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
  if (argc > 2) {
    if (!load_ply(pc, argv[2])) {
      std::fprintf(stderr, "failed to load %s\n", argv[2]);
      return 2;
    }
  } else {
    pc = generate_road_scan();
  }
  std::fprintf(stderr, "points: %zu\n", pc.size());

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
  r.upload(pc);
  const Bounds b = r.bounds();

  // Orbit camera: look down at the road strip from an angle.
  QMatrix4x4 proj;
  proj.perspective(45.0f, static_cast<float>(W) / H, 0.05f, 1000.0f);
  QMatrix4x4 view;
  const float dist = b.radius * 1.15f;
  // Lower, three-quarter angle so the potholes read as real depressions.
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
