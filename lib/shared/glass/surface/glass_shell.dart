import 'dart:ui' as ui;

import 'package:flutter/widgets.dart';

import 'liquid_surface.dart';

class GlassShell extends StatelessWidget {
  const GlassShell({
    required this.path,
    required this.glowCenter,
    required this.press,
    required this.focused,
    this.blurSigma,
    super.key,
  });

  final Path path;
  final Offset glowCenter;
  final double press;
  final bool focused;

  /// Adaptive backdrop sigma. Null (or rest value) reuses the single shared
  /// [LiquidBlur.filter]; reduced sigmas resolve through a small quantized
  /// cache (0.5 steps) so no filter object is allocated per frame.
  final double? blurSigma;

  static ui.ImageFilter get backdropBlur => LiquidBlur.filter;

  @override
  Widget build(BuildContext context) {
    final motionSigma = blurSigma;
    final transitionSigma = LiquidBlurScope.maybeOf(context);
    final transitionOpacity = LiquidBlurScope.maybeOpacityOf(context) ?? 1.0;
    final double? sigma;
    if (transitionSigma == null) {
      sigma = motionSigma;
    } else if (motionSigma == null) {
      sigma = transitionSigma;
    } else {
      sigma = motionSigma < transitionSigma ? motionSigma : transitionSigma;
    }
    return RepaintBoundary(
      child: CustomPaint(
        painter: _ShellShadowPainter(path, opacity: transitionOpacity),
        child: Stack(
          fit: StackFit.expand,
          children: <Widget>[
            ClipPath(
              clipper: _ShellClipper(path),
              child: BackdropFilter.grouped(
                filter: sigma == null
                    ? backdropBlur
                    : LiquidBlur.filterFor(sigma),
                child: CustomPaint(
                  painter: const _CoveragePainter(),
                  child: const SizedBox.expand(),
                ),
              ),
            ),
            Opacity(
              opacity: transitionOpacity,
              child: CustomPaint(
                painter: _ShellPainter(
                  path: path,
                  glowCenter: glowCenter,
                  press: press,
                  focused: focused,
                ),
              ),
            ),
          ],
        ),
      ),
    );
  }
}

class _CoveragePainter extends CustomPainter {
  const _CoveragePainter();

  @override
  void paint(Canvas canvas, Size size) {
    final paint = Paint()..color = const Color.fromARGB(1, 0, 0, 0);
    canvas.drawPoints(ui.PointMode.points, <Offset>[
      Offset.zero,
      Offset(size.width - 1, 0),
      Offset(0, size.height - 1),
      Offset(size.width - 1, size.height - 1),
    ], paint);
  }

  @override
  bool shouldRepaint(covariant _CoveragePainter oldDelegate) => false;
}

class _ShellClipper extends CustomClipper<Path> {
  const _ShellClipper(this.path);

  final Path path;

  @override
  Path getClip(Size size) => path;

  @override
  bool shouldReclip(covariant _ShellClipper oldClipper) =>
      oldClipper.path != path;
}

class _ShellShadowPainter extends CustomPainter {
  const _ShellShadowPainter(this.path, {required this.opacity});

  final Path path;
  final double opacity;

  /// Fully static config: shared across frames/canvases instead of being
  /// reallocated on every repaint. Pixel-identical output.
  static final Paint _shadowPaint = Paint()
    ..color = const Color(0xFF020809).withValues(alpha: 0.24)
    ..maskFilter = const MaskFilter.blur(BlurStyle.normal, 12);

  @override
  void paint(Canvas canvas, Size size) {
    final outside = Path.combine(
      PathOperation.difference,
      Path()..addRect((Offset.zero & size).inflate(32)),
      path,
    );
    final shadowPaint = opacity >= 0.999 ? _shadowPaint : Paint()
      ..color = const Color(0xFF020809).withValues(alpha: 0.24 * opacity)
      ..maskFilter = const MaskFilter.blur(BlurStyle.normal, 12);
    canvas.save();
    canvas.clipPath(outside);
    canvas.drawPath(path.shift(const Offset(0, 7)), shadowPaint);
    canvas.restore();
  }

  @override
  bool shouldRepaint(covariant _ShellShadowPainter oldDelegate) =>
      oldDelegate.path != path || oldDelegate.opacity != opacity;
}

class _ShellPainter extends CustomPainter {
  const _ShellPainter({
    required this.path,
    required this.glowCenter,
    required this.press,
    required this.focused,
  });

  final Path path;
  final Offset glowCenter;
  final double press;
  final bool focused;

  /// Fully static paint configs: shared instead of reallocated per repaint.
  static final Paint _fillPaint = Paint()..color = const Color(0x14F2F2F0);
  static final Paint _innerWidePaint = Paint()
    ..style = PaintingStyle.stroke
    ..strokeWidth = 11
    ..color = const Color(0xFFFFFFFF).withValues(alpha: 0.05)
    ..maskFilter = const MaskFilter.blur(BlurStyle.inner, 6);
  static final Paint _innerNarrowPaint = Paint()
    ..style = PaintingStyle.stroke
    ..strokeWidth = 5
    ..color = const Color(0xFFFFFFFF).withValues(alpha: 0.10)
    ..maskFilter = const MaskFilter.blur(BlurStyle.inner, 3);

  /// Rim gradient is constant; only its shader depends on [size], which is
  /// stable per surface. Cached instead of recreated every frame.
  static const LinearGradient _rimGradient = LinearGradient(
    begin: Alignment.topLeft,
    end: Alignment.bottomRight,
    colors: <Color>[
      Color(0x82FFFFFF),
      Color(0x68E6E6E4),
      Color(0x48AFAFAD),
      Color(0x72F4F4F2),
      Color(0x3C9A9A98),
    ],
    stops: <double>[0, 0.25, 0.48, 0.74, 1],
  );
  static final Map<Size, ui.Shader> _rimShaderCache = <Size, ui.Shader>{};

  static ui.Shader _rimShaderFor(Size size) {
    var shader = _rimShaderCache[size];
    if (shader == null) {
      // Surface sizes are stable and few; still, never grow unbounded.
      if (_rimShaderCache.length > 32) {
        _rimShaderCache.clear();
      }
      shader = _rimGradient.createShader(Offset.zero & size);
      _rimShaderCache[size] = shader;
    }
    return shader;
  }

  @override
  void paint(Canvas canvas, Size size) {
    canvas.drawPath(path, _fillPaint);
    canvas.save();
    canvas.clipPath(path);
    canvas.drawPath(path, _innerWidePaint);
    canvas.drawPath(path, _innerNarrowPaint);
    canvas.restore();
    final pressAmount = press.clamp(0.0, 1.0);
    if (pressAmount > 0.01) {
      canvas.save();
      canvas.clipPath(path);
      canvas.drawCircle(
        glowCenter,
        132,
        Paint()
          ..shader = ui.Gradient.radial(
            glowCenter,
            132,
            <Color>[
              const Color(0xFFFFFFFF).withValues(alpha: pressAmount * 0.175),
              const Color(0x28F3F3F0).withValues(alpha: 0.157 * pressAmount),
              const Color(0x00FFFFFF),
            ],
            <double>[0, 0.42, 1],
          ),
      );
      canvas.restore();
    }

    final rim = Paint()
      ..style = PaintingStyle.stroke
      ..strokeWidth = focused ? 1.15 : 0.82
      ..shader = _rimShaderFor(size);
    canvas.drawPath(path, rim);

    if (pressAmount > 0.01) {
      canvas.drawPath(
        path,
        Paint()
          ..style = PaintingStyle.stroke
          ..strokeWidth = focused ? 1.32 : 0.92
          ..shader = ui.Gradient.radial(
            glowCenter,
            156,
            <Color>[
              const Color(0xFFFFFFFF).withValues(alpha: pressAmount * 0.32),
              const Color(0x18E2E2E0).withValues(alpha: 0.094 * pressAmount),
              const Color(0x00FFFFFF),
            ],
            <double>[0, 0.46, 1],
          ),
      );
    }
  }

  @override
  bool shouldRepaint(covariant _ShellPainter oldDelegate) =>
      oldDelegate.path != path ||
      oldDelegate.glowCenter != glowCenter ||
      oldDelegate.press != press ||
      oldDelegate.focused != focused;
}
