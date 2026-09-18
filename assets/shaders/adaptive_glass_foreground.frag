#version 320 es

#include <flutter/runtime_effect.glsl>

// ImageFilter.shader supplies u_size and the first sampler. The second sampler
// is the cached glyph alpha mask supplied by Dart.
uniform vec2 u_size;
uniform vec4 u_mask_bounds;
uniform vec2 u_sample_point;
uniform sampler2D u_backdrop;
uniform sampler2D u_glyph_mask;

out vec4 frag_color;

vec3 linearize_srgb(vec3 color) {
  vec3 low = color / 12.92;
  vec3 high = pow((color + vec3(0.055)) / 1.055, vec3(2.4));
  return mix(low, high, step(vec3(0.04045), color));
}

float backdrop_luminance(vec2 uv) {
  vec3 sample_color = texture(
    u_backdrop,
    clamp(uv, vec2(0.0), vec2(1.0))
  ).rgb;
  return dot(
    linearize_srgb(sample_color),
    vec3(0.2126, 0.7152, 0.0722)
  );
}

void main() {
  vec2 pixel = FlutterFragCoord().xy;

  // Impeller's OpenGL backend exposes filter textures upside-down.
#ifdef IMPELLER_TARGET_OPENGLES
  pixel.y = u_size.y - pixel.y;
#endif

  vec2 sample_uv = clamp(u_sample_point / u_size, vec2(0.0), vec2(1.0));
  vec2 sample_step = 2.0 / u_size;
  float luminance = (
    backdrop_luminance(sample_uv) +
    backdrop_luminance(sample_uv + vec2(-sample_step.x, 0.0)) +
    backdrop_luminance(sample_uv + vec2(sample_step.x, 0.0)) +
    backdrop_luminance(sample_uv + vec2(0.0, -sample_step.y)) +
    backdrop_luminance(sample_uv + vec2(0.0, sample_step.y))
  ) / 5.0;

  // Ease through a narrow luminance band so foreground changes follow an
  // animated/scrolling backdrop without a visible one-frame color snap.
  // Outside the transition band the result is still pure black or white.
  float dark_foreground = smoothstep(0.164, 0.194, luminance);
  vec3 foreground = mix(vec3(1.0), vec3(0.0), dark_foreground);
  vec2 mask_uv = clamp(
    (pixel - u_mask_bounds.xy) / u_mask_bounds.zw,
    vec2(0.0),
    vec2(1.0)
  );
  float glyph_alpha = texture(u_glyph_mask, mask_uv).a;
  frag_color = vec4(foreground * glyph_alpha, glyph_alpha);
}
