import { glsl } from "./Tags";

export const Core = glsl`
const float PI = ${Math.PI};
const vec4 TRANSPARENT = vec4(0.0, 0.0, 0.0, 0.0);

struct Context {
  vec4 color;
  vec2 p;
  vec2 resolution;
};

mat3 translate(vec2 t) {
  return mat3(
    1.0, 0.0, 0.0,
    0.0, 1.0, 0.0,
    t.x, t.y, 1.0
  );
}

mat3 scale(vec2 s, vec2 center) {
  return translate(center) * mat3(
    s.x, 0.0, 0.0,
    0.0, s.y, 0.0,
    0.0, 0.0, 1.0
  ) * translate(-center);
}

vec2 project(vec2 p, mat3 m) {
  mat3 inv = mat3(
    m[0][0], m[1][0], m[2][0],
    m[0][1], m[1][1], m[2][1],
    m[0][2], m[1][2], m[2][2]
  );
  // Simple inverse for scale+translate matrices
  float det = m[0][0] * m[1][1] - m[0][1] * m[1][0];
  if (abs(det) < 0.0001) {
    return p;
  }
  inv[0][0] = m[1][1] / det;
  inv[1][1] = m[0][0] / det;
  inv[0][1] = -m[0][1] / det;
  inv[1][0] = -m[1][0] / det;
  inv[2][0] = (m[1][0] * m[2][1] - m[1][1] * m[2][0]) / det;
  inv[2][1] = (m[0][1] * m[2][0] - m[0][0] * m[2][1]) / det;

  vec3 result = vec3(p, 1.0) * inv;
  return result.xy;
}
`;
