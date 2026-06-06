#include "gl_renderer.h"

#include <vector>

namespace aurum::pcv {

namespace {
// Interleaved layout per point: x,y,z,defect (4 floats).
constexpr int kStride = 4 * sizeof(float);

const char *kVert = R"(#version 330 core
layout(location=0) in vec3 inPos;
layout(location=1) in float inDefect;
uniform mat4 uMVP;
uniform float uPointSize;
out float vDefect;
void main() {
    vDefect = inDefect;
    gl_Position = uMVP * vec4(inPos, 1.0);
    gl_PointSize = uPointSize;
}
)";

// Same green->yellow->red mapping as defect_color(), on the GPU.
const char *kFrag = R"(#version 330 core
in float vDefect;
out vec4 fragColor;
void main() {
    float s = clamp(vDefect, 0.0, 1.0);
    vec3 c;
    if (s < 0.5) { c = vec3(s / 0.5, 1.0, 0.0); }
    else         { c = vec3(1.0, 1.0 - (s - 0.5) / 0.5, 0.0); }
    // Round point sprites for a cleaner look.
    vec2 d = gl_PointCoord - vec2(0.5);
    if (dot(d, d) > 0.25) discard;
    fragColor = vec4(c, 1.0);
}
)";
} // namespace

void GLRenderer::init() {
  initializeOpenGLFunctions();
  m_prog.addShaderFromSourceCode(QOpenGLShader::Vertex, kVert);
  m_prog.addShaderFromSourceCode(QOpenGLShader::Fragment, kFrag);
  m_prog.link();
  m_vao.create();
  m_vbo = std::make_unique<QOpenGLBuffer>(QOpenGLBuffer::VertexBuffer);
  m_vbo->create();
  m_ready = true;
}

void GLRenderer::upload(const PointCloud &pc) {
  m_count = pc.size();
  m_bounds = compute_bounds(pc);

  // Interleave xyz+defect.
  std::vector<float> interleaved;
  interleaved.reserve(m_count * 4);
  for (std::size_t i = 0; i < m_count; ++i) {
    interleaved.push_back(pc.xyz[3 * i]);
    interleaved.push_back(pc.xyz[3 * i + 1]);
    interleaved.push_back(pc.xyz[3 * i + 2]);
    interleaved.push_back(pc.defect[i]);
  }

  m_vao.bind();
  m_vbo->bind();
  m_vbo->allocate(interleaved.data(),
                  static_cast<int>(interleaved.size() * sizeof(float)));
  m_prog.bind();
  m_prog.enableAttributeArray(0);
  m_prog.setAttributeBuffer(0, GL_FLOAT, 0, 3, kStride);
  m_prog.enableAttributeArray(1);
  m_prog.setAttributeBuffer(1, GL_FLOAT, 3 * sizeof(float), 1, kStride);
  m_prog.release();
  m_vbo->release();
  m_vao.release();
}

void GLRenderer::render(const QMatrix4x4 &mvp, int vw, int vh,
                        float pointSize) {
  if (!m_ready || m_count == 0)
    return;
  glViewport(0, 0, vw, vh);
  glEnable(GL_DEPTH_TEST);
  glEnable(0x8642 /*GL_PROGRAM_POINT_SIZE*/);
  glClearColor(0.07f, 0.07f, 0.09f, 1.0f);
  glClear(GL_COLOR_BUFFER_BIT | GL_DEPTH_BUFFER_BIT);

  m_prog.bind();
  m_prog.setUniformValue("uMVP", mvp);
  m_prog.setUniformValue("uPointSize", pointSize);
  m_vao.bind();
  glDrawArrays(GL_POINTS, 0, static_cast<int>(m_count));
  m_vao.release();
  m_prog.release();
}

} // namespace aurum::pcv
