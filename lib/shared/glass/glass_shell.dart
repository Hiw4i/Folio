import 'dart:ui' as ui;

import 'package:flutter/widgets.dart';

import 'glass_tokens.dart';

class GlassShell extends StatelessWidget {
  const GlassShell({
    required this.path,
    required this.glowCenter,
    required this.press,
    required this.focused,
    super.key,
  });

  final Path path;
  final Offset glowCenter;
  final double press;
  final bool focused;

  static final ui.ImageFilter backdropBlur = ui.ImageFilter.blur(
    sigmaX: const GlassTokens().blurSigma,
    sigmaY: const GlassTokens().blurSigma,
    tileMode: ui.TileMode.mirror,
  );

  @override
  Widget build(BuildContext context) {
    return RepaintBoundary(
      child: CustomPaint(
        painter: _ShellShadowPainter(path),
        child: Stack(
          fit: StackFit.expand,
          children: <Widget>[
            ClipPath(
              clipper: _ShellClipper(path),
              child: BackdropFilter(
                filter: backdropBlur,
                child: CustomPaint(
                  painter: const _CoveragePainter(),
                  child: const SizedBox.expand(),
                ),
              ),
            ),
            CustomPaint(
              painter: _ShellPainter(
                path: path,
                glowCenter: glowCenter,
                press: press,
                focused: focused,
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
  const _ShellShadowPainter(this.path);

  final Path path;

  @override
  void paint(Canvas canvas, Size size) {
    final outside = Path.combine(
      PathOperation.difference,
      Path()..addRect((Offset.zero & size).inflate(32)),
      path,
    );
    canvas.save();
    canvas.clipPath(outside);
    canvas.drawPath(
      path.shift(const Offset(0, 7)),
      Paint()
        ..color = const Color(0xFF020809).withValues(alpha: 0.24)
        ..maskFilter = const MaskFilter.blur(BlurStyle.normal, 12),
    );
    canvas.restore();
  }

  @override
  bool shouldRepaint(covariant _ShellShadowPainter oldDelegate) =>
      oldDelegate.path != path;
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

  @override
  void paint(Canvas canvas, Size size) {
    canvas.drawPath(path, Paint()..color = const Color(0x14F2F2F0));
    canvas.save();
    canvas.clipPath(path);
    canvas.drawPath(
      path,
      Paint()
        ..style = PaintingStyle.stroke
        ..strokeWidth = 11
        ..color = const Color(0xFFFFFFFF).withValues(alpha: 0.05)
        ..maskFilter = const MaskFilter.blur(BlurStyle.inner, 6),
    );
    canvas.drawPath(
      path,
      Paint()
        ..style = PaintingStyle.stroke
        ..strokeWidth = 5
        ..color = const Color(0xFFFFFFFF).withValues(alpha: 0.10)
        ..maskFilter = const MaskFilter.blur(BlurStyle.inner, 3),
    );
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
      ..shader = const LinearGradient(
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
      ).createShader(Offset.zero & size);
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
