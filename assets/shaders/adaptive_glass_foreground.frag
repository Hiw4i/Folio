#version 320 es

#include <flutter/runtime_effect.glsl>

// Engine-owned input size and first sampler. All positions below are physical
// coordinates in the root backdrop, never in an Opacity/ImageFiltered buffer.
uniform vec2 u_size;
uniform vec2 u_mask_origin;
uniform vec2 u_mask_inverse_x;
uniform vec2 u_mask_inverse_y;
uniform vec2 u_sample_point;
uniform float u_opacity;
uniform sampler2D u_backdrop;
uniform sampler2D u_glyph_mask;

out vec4 frag_color;

vec3 linearize_srgb(vec3 color) {
  vec3 low = color / 12.92;
  vec3 high = pow((color + vec3(0.055)) / 1.055, vec3(2.4));
  return mix(low, high, step(vec3(0.04045), color));
}

float backdrop_luminance(vec2 pixel) {
  vec2 uv = clamp(pixel / u_size, vec2(0.0), vec2(1.0));
  // Only the engine-provided texture is upside-down on GLES. Do not flip
  // FlutterFragCoord or the Dart-created glyph mask / its screen-space bounds.
#ifdef IMPELLER_TARGET_OPENGLES
  uv.y = 1.0 - uv.y;
#endif
  vec4 backdrop = texture(u_backdrop, uv);
  vec3 color = backdrop.a > 0.0001
      ? clamp(backdrop.rgb / backdrop.a, vec3(0.0), vec3(1.0))
      : vec3(0.0);
  return dot(linearize_srgb(color), vec3(0.2126, 0.7152, 0.0722));
}

void main() {
  vec2 delta = FlutterFragCoord().xy - u_mask_origin;
  vec2 mask_uv = vec2(
    dot(delta, u_mask_inverse_x),
    dot(delta, u_mask_inverse_y)
  );
  // The filter's input also covers the common sample patch. Never extend
  // clamp-to-edge glyph pixels over that extra area (or recolor the surface).
  if (u_opacity <= 0.0 || any(lessThan(mask_uv, vec2(0.0))) ||
      any(greaterThan(mask_uv, vec2(1.0)))) {
    frag_color = vec4(0.0);
    return;
  }
  float alpha = texture(u_glyph_mask, mask_uv).a * u_opacity;
  if (alpha <= 0.0) {
    // Text rectangles are mostly empty. Avoid five texture reads and sRGB
    // conversions there, rather than shading every transparent fragment.
    frag_color = vec4(0.0);
    return;
  }
  // Same location for every glyph in a control, independent of glyph bounds,
  // fades, press scale and motion blur. Each control supplies its own location.
  float luminance = (
    backdrop_luminance(u_sample_point) +
    backdrop_luminance(u_sample_point + vec2(-2.0, 0.0)) +
    backdrop_luminance(u_sample_point + vec2(2.0, 0.0)) +
    backdrop_luminance(u_sample_point + vec2(0.0, -2.0)) +
    backdrop_luminance(u_sample_point + vec2(0.0, 2.0))
  ) / 5.0;
  float dark_foreground = smoothstep(0.164, 0.194, luminance);
  vec3 foreground = vec3(1.0 - dark_foreground);
  frag_color = vec4(foreground * alpha, alpha);
}
