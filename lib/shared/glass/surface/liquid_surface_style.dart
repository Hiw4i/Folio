import 'dart:ui' as ui;

import 'package:flutter/widgets.dart';

/// Paint shared by deforming buttons, static panels and segmented tracks.
/// Optical detail is independent of the optional backdrop blur.
abstract final class LiquidSurfaceStyle {
  /// Slightly lighter than the old #202123 fallback, still dark enough for
  /// the fixed light foreground used when backdrop adaptation is disabled.
  static const Color opaqueFill = Color(0xFF292A2D);

  /// A broad upper-left reflection, a softer opposing one and quiet sides.
  /// Equal first/last colours make the angular seam invisible. No ticker or
  /// extra backdrop pass is needed; the light follows the surface geometry.
  static const SweepGradient rimGradient = SweepGradient(
    colors: <Color>[
      Color(0x26FFFFFF),
      Color(0x66FFFFFF),
      Color(0x20FFFFFF),
      Color(0x0DFFFFFF),
      Color(0x33FFFFFF),
      Color(0x99FFFFFF),
      Color(0x4DFFFFFF),
      Color(0x14FFFFFF),
      Color(0x26FFFFFF),
    ],
    stops: <double>[0, 0.125, 0.25, 0.375, 0.5, 0.625, 0.75, 0.875, 1],
  );

  // Bounds, not the optical canvas (which includes large transparent
  // margins), determine the reflection. Limit native shaders during morphs.
  static const int _maxCachedRims = 32;
  static final Map<Rect, ui.Shader> _rimShaders = <Rect, ui.Shader>{};

  static ui.Shader _rimShaderFor(Rect bounds) {
    final cached = _rimShaders[bounds];
    if (cached != null) return cached;
    if (_rimShaders.length >= _maxCachedRims) {
      _rimShaders.remove(_rimShaders.keys.first);
    }
    return _rimShaders[bounds] = rimGradient.createShader(bounds);
  }

  static void paintRim(
    Canvas canvas,
    Path path, {
    required Rect bounds,
    double width = 0.82,
  }) {
    if (bounds.isEmpty || !bounds.isFinite) return;
    canvas.drawPath(
      path,
      Paint()
        ..style = PaintingStyle.stroke
        ..strokeWidth = width
        ..shader = _rimShaderFor(bounds),
    );
  }
}

/// Static cases use the same rim as GlassShell, without a uniform border
/// underneath. Inset by half the stroke so ClipRRect cannot cut it in half.
class LiquidCaseRimPainter extends CustomPainter {
  const LiquidCaseRimPainter({required this.radius});

  final BorderRadius radius;
  static const double _width = 0.8;

  @override
  void paint(Canvas canvas, Size size) {
    if (!size.isFinite || size.shortestSide <= _width) return;
    final rect = Offset.zero & size;
    final rim = radius.toRRect(rect).deflate(_width / 2);
    LiquidSurfaceStyle.paintRim(
      canvas,
      Path()..addRRect(rim),
      bounds: rect,
      width: _width,
    );
  }

  @override
  bool shouldRepaint(covariant LiquidCaseRimPainter oldDelegate) =>
      oldDelegate.radius != radius;

  @override
  bool? hitTest(Offset position) => false;
}
