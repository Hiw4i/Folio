import 'package:flutter/services.dart';
import 'package:flutter/widgets.dart';

import '../selection/folio_selection_toolbar.dart';
import 'glass_geometry.dart';
import 'glass_motion_controller.dart';
import 'glass_surface.dart';
import 'glass_touch_shield.dart';
import 'liquid_content.dart';
import 'liquid_shape.dart';

class LiquidSearchMorph extends StatelessWidget {
  const LiquidSearchMorph({
    required this.frame,
    required this.motion,
    required this.searchController,
    required this.editableKey,
    required this.searchFocus,
    required this.mainFocus,
    required this.cancelFocus,
    required this.reducedMotion,
    required this.hintText,
    required this.semanticsLabel,
    required this.onTapInput,
    this.onSubmitted,
    super.key,
  });

  final GlassGeometryFrame frame;
  final GlassMotionController motion;
  final TextEditingController searchController;
  final GlobalKey<EditableTextState> editableKey;
  final FocusNode searchFocus;
  final FocusNode mainFocus;
  final FocusNode cancelFocus;
  final bool reducedMotion;
  final String hintText;
  final String semanticsLabel;
  final VoidCallback onTapInput;
  final ValueChanged<String>? onSubmitted;

  @override
  Widget build(BuildContext context) {
    final contentOpacity = ((frame.morph - 0.52) / 0.30).clamp(0.0, 1.0);
    final cancelOpacity = ((frame.separation - 0.45) / 0.42).clamp(0.0, 1.0);
    final selfBlur = LiquidContent.blurSigma(
      morphVelocity: motion.morphVelocity,
      separationVelocity: motion.separationVelocity,
      reducedMotion: reducedMotion,
    );
    final mainContentOffset = LiquidContent.offset(
      displacement: frame.mainDeformation,
      velocity: frame.deformationVelocity,
      press: frame.deformCancel ? 0 : frame.press,
    );
    final cancelContentOffset = LiquidContent.offset(
      displacement: frame.cancelDeformation,
      velocity: frame.deformationVelocity,
      press: frame.deformCancel ? frame.press : 0,
    );

    Widget soften(Widget child) =>
        LiquidContent.soften(child: child, sigma: selfBlur);

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
        Positioned.fromRect(
          rect: frame.mainRect.inflate(8),
          child: const GlassTouchShield(),
        ),
        if (frame.cancelVisible)
          Positioned.fromRect(
            rect: frame.cancelRect.inflate(6),
            child: const GlassTouchShield(),
          ),
        Positioned(
          left: frame.iconCenter.dx - 12,
          top: frame.iconCenter.dy - 12,
          width: 24,
          height: 24,
          child: IgnorePointer(
            child: soften(
              Transform.scale(
                scale: LiquidShape.contentScale(
                  frame.deformCancel ? 0 : frame.press,
                ),
                child: CustomPaint(
                  painter: _SearchPainter(
                    opacity: 0.88 + motion.submitEnergy * 0.12,
                  ),
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
          ).shift(mainContentOffset),
          child: IgnorePointer(
            ignoring: frame.morph < 0.76 || !motion.wantsOpen,
            child: MouseRegion(
              cursor: SystemMouseCursors.text,
              opaque: false,
              child: ExcludeSemantics(
                excluding: frame.morph < 0.76 || !motion.wantsOpen,
                child: Listener(
                  behavior: HitTestBehavior.translucent,
                  onPointerDown: (_) => onTapInput(),
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
                                child: Text(
                                  hintText,
                                  maxLines: 1,
                                  overflow: TextOverflow.fade,
                                  softWrap: false,
                                  style: const TextStyle(
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
                            key: const ValueKey<String>('search_editable'),
                            label: semanticsLabel,
                            textField: true,
                            child: EditableText(
                              key: editableKey,
                              controller: searchController,
                              focusNode: searchFocus,
                              contextMenuBuilder:
                                  folioEditableTextContextMenuBuilder,
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
                              onSubmitted: (value) {
                                motion.submit();
                                onSubmitted?.call(value);
                              },
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
        ),
        if (frame.cancelVisible)
          Positioned.fromRect(
            rect: frame.cancelRect.shift(cancelContentOffset),
            child: IgnorePointer(
              child: soften(
                Opacity(
                  opacity: cancelOpacity,
                  child: Transform.scale(
                    scale: LiquidShape.contentScale(
                      frame.deformCancel ? frame.press : 0,
                    ),
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
          ),
        if (frame.morph < 0.68)
          Positioned.fromRect(
            rect: frame.mainRect.inflate(8),
            child: MouseRegion(
              cursor: SystemMouseCursors.click,
              opaque: false,
              child: Semantics(
                button: true,
                label: semanticsLabel,
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
