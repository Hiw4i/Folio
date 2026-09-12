import 'dart:ui' as ui;

import 'package:flutter/services.dart';
import 'package:flutter/widgets.dart';

import 'glass_geometry.dart';
import 'glass_motion_controller.dart';
import 'glass_surface.dart';

class LiquidSearchMorph extends StatelessWidget {
  const LiquidSearchMorph({
    required this.frame,
    required this.motion,
    required this.searchController,
    required this.searchFocus,
    required this.mainFocus,
    required this.cancelFocus,
    required this.reducedMotion,
    super.key,
  });

  final GlassGeometryFrame frame;
  final GlassMotionController motion;
  final TextEditingController searchController;
  final FocusNode searchFocus;
  final FocusNode mainFocus;
  final FocusNode cancelFocus;
  final bool reducedMotion;

  @override
  Widget build(BuildContext context) {
    final contentOpacity = ((frame.morph - 0.52) / 0.30).clamp(0.0, 1.0);
    final cancelOpacity = ((frame.separation - 0.45) / 0.42).clamp(0.0, 1.0);
    final velocityBlur =
        motion.morphVelocity.abs() * 0.22 +
        motion.separationVelocity.abs() * 0.15;
    final selfBlur = (velocityBlur * (reducedMotion ? 0.32 : 1.0)).clamp(
      0.0,
      2.15,
    );

    Widget soften(Widget child) {
      if (selfBlur <= 0.01) {
        return child;
      }
      return ImageFiltered(
        imageFilter: ui.ImageFilter.blur(
          sigmaX: selfBlur,
          sigmaY: selfBlur,
          tileMode: ui.TileMode.decal,
        ),
        child: child,
      );
    }

    return Stack(
      fit: StackFit.expand,
      children: <Widget>[
        LiquidGlassSurface(
          frame: frame,
          motion: motion,
          focused:
              searchFocus.hasFocus ||
              cancelFocus.hasFocus ||
              mainFocus.hasFocus,
        ),
        Positioned(
          left: frame.iconCenter.dx - 12,
          top: frame.iconCenter.dy - 12,
          width: 24,
          height: 24,
          child: IgnorePointer(
            child: soften(
              CustomPaint(
                painter: _SearchPainter(
                  opacity: 0.88 + motion.submitEnergy * 0.12,
                ),
              ),
            ),
          ),
        ),
        Positioned.fromRect(
          rect: Rect.fromLTRB(
            frame.mainRect.left + 54,
            frame.mainRect.center.dy - 19,
            frame.mainRect.right - 18,
            frame.mainRect.center.dy + 19,
          ),
          child: IgnorePointer(
            ignoring: frame.morph < 0.76 || !motion.wantsOpen,
            child: MouseRegion(
              cursor: SystemMouseCursors.text,
              opaque: false,
              child: ExcludeSemantics(
                excluding: frame.morph < 0.76 || !motion.wantsOpen,
                child: soften(
                  Opacity(
                    opacity: contentOpacity,
                    child: Stack(
                      alignment: Alignment.centerLeft,
                      children: <Widget>[
                        ValueListenableBuilder<TextEditingValue>(
                          valueListenable: searchController,
                          builder: (context, value, child) {
                            return Offstage(
                              offstage: value.text.isNotEmpty,
                              child: const Text(
                                'Search documents',
                                maxLines: 1,
                                overflow: TextOverflow.fade,
                                softWrap: false,
                                style: TextStyle(
                                  fontFamily: 'Inter',
                                  color: Color(0x99EDECE8),
                                  fontSize: 16,
                                  letterSpacing: 0.1,
                                ),
                              ),
                            );
                          },
                        ),
                        Semantics(
                          label: 'Search documents',
                          textField: true,
                          child: EditableText(
                            key: const ValueKey<String>('search_editable'),
                            controller: searchController,
                            focusNode: searchFocus,
                            style: const TextStyle(
                              fontFamily: 'Inter',
                              color: Color(0xFFF4F3EF),
                              fontSize: 16,
                              height: 1.2,
                            ),
                            cursorColor: const Color(0xFFE7C768),
                            backgroundCursorColor: const Color(0xFF736A4C),
                            selectionColor: const Color(0x55E7C768),
                            maxLines: 1,
                            keyboardType: TextInputType.text,
                            textInputAction: TextInputAction.search,
                            onSubmitted: (_) => motion.submit(),
                          ),
                        ),
                      ],
                    ),
                  ),
                ),
              ),
            ),
          ),
        ),
        if (frame.cancelVisible)
          Positioned.fromRect(
            rect: frame.cancelRect,
            child: IgnorePointer(
              child: soften(
                Opacity(
                  opacity: cancelOpacity,
                  child: const Center(
                    child: Text(
                      'Cancel',
                      maxLines: 1,
                      style: TextStyle(
                        fontFamily: 'Inter',
                        color: Color(0xFFF4F3EF),
                        fontSize: 14.5,
                        fontWeight: FontWeight.w500,
                        letterSpacing: 0.1,
                      ),
                    ),
                  ),
                ),
              ),
            ),
          ),
        if (frame.morph < 0.68)
          Positioned.fromRect(
            rect: frame.mainRect.inflate(8),
            child: MouseRegion(
              cursor: SystemMouseCursors.click,
              opaque: false,
              child: Semantics(
                button: true,
                label: 'Search',
                onTap: () {
                  mainFocus.requestFocus();
                  motion.requestOpen();
                },
                child: Focus(
                  key: const ValueKey<String>('search_button_hit'),
                  focusNode: mainFocus,
                  onKeyEvent: (node, event) {
                    if (event is KeyDownEvent &&
                        (event.logicalKey == LogicalKeyboardKey.enter ||
                            event.logicalKey == LogicalKeyboardKey.space)) {
                      motion.requestOpen();
                      return KeyEventResult.handled;
                    }
                    return KeyEventResult.ignored;
                  },
                  child: const SizedBox.expand(),
                ),
              ),
            ),
          ),
        if (frame.cancelInteractive)
          Positioned.fromRect(
            rect: frame.cancelRect.inflate(6),
            child: MouseRegion(
              cursor: SystemMouseCursors.click,
              opaque: false,
              child: Semantics(
                container: true,
                explicitChildNodes: true,
                button: true,
                label: 'Cancel',
                onTap: motion.requestClose,
                child: Focus(
                  key: const ValueKey<String>('cancel_button_hit'),
                  focusNode: cancelFocus,
                  onKeyEvent: (node, event) {
                    if (event is KeyDownEvent &&
                        (event.logicalKey == LogicalKeyboardKey.enter ||
                            event.logicalKey == LogicalKeyboardKey.space)) {
                      motion.requestClose();
                      return KeyEventResult.handled;
                    }
                    return KeyEventResult.ignored;
                  },
                  child: const SizedBox.expand(),
                ),
              ),
            ),
          ),
      ],
    );
  }
}

class _SearchPainter extends CustomPainter {
  const _SearchPainter({required this.opacity});

  final double opacity;

  @override
  void paint(Canvas canvas, Size size) {
    final scale = size.shortestSide / 24;
    final paint = Paint()
      ..color = const Color(0xFFF4F3EF).withValues(alpha: opacity.clamp(0, 1))
      ..style = PaintingStyle.stroke
      ..strokeWidth = 2 * scale
      ..strokeCap = StrokeCap.round
      ..strokeJoin = StrokeJoin.round;
    canvas.drawCircle(Offset(11 * scale, 11 * scale), 8 * scale, paint);
    canvas.drawLine(
      Offset(16.66 * scale, 16.66 * scale),
      Offset(21 * scale, 21 * scale),
      paint,
    );
  }

  @override
  bool shouldRepaint(covariant _SearchPainter oldDelegate) =>
      oldDelegate.opacity != opacity;
}
