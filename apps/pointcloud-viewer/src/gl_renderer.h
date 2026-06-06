#pragma once
#include <QMatrix4x4>
#include <QOpenGLBuffer>
#include <QOpenGLFunctions>
#include <QOpenGLShaderProgram>
#include <QOpenGLVertexArrayObject>
#include <memory>

#include "point_cloud.h"

namespace aurum::pcv {

// Renders a PointCloud as GPU points, coloured by defect score on the GPU.
// Backend-agnostic: the caller owns the GL context/surface (an interactive
// window or an offscreen FBO), makes it current, then calls init()/upload()/
// render(). Keeps the whole cloud in one interleaved VBO so draw is one call.
class GLRenderer : protected QOpenGLFunctions {
public:
  void init();                       // compile shaders, create VAO/VBO
  void upload(const PointCloud &pc); // push geometry+defect to the GPU
  void render(const QMatrix4x4 &mvp, int viewportW, int viewportH,
              float pointSize = 2.0f);

  const Bounds &bounds() const { return m_bounds; }
  std::size_t pointCount() const { return m_count; }

private:
  QOpenGLShaderProgram m_prog;
  QOpenGLVertexArrayObject m_vao;
  std::unique_ptr<QOpenGLBuffer> m_vbo;
  std::size_t m_count{0};
  Bounds m_bounds;
  bool m_ready{false};
};

} // namespace aurum::pcv
