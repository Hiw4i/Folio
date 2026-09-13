import 'package:flutter/services.dart';
import 'package:flutter/widgets.dart';

import 'glass_button_controller.dart';
import 'glass_geometry.dart';
import 'glass_shell.dart';
import 'glass_touch_shield.dart';
import 'liquid_shape.dart';

/// Reusable liquid-glass interaction primitive for text, icons and future
/// compound controls. It owns hit testing, focus, pointer physics and painting;
/// callers only provide content and an action.
class LiquidGlassControl extends StatefulWidget {
  const LiquidGlassControl({
    required this.child,
    required this.size,
    this.onTap,
    this.semanticsLabel,
    this.shapeTokens = const LiquidShapeTokens(),
    this.hitSlop = 8,
    super.key,
  });

  final Widget child;
  final VoidCallback? onTap;
  final String? semanticsLabel;
  final Size size;
  final LiquidShapeTokens shapeTokens;
  final double hitSlop;

  @override
  State<LiquidGlassControl> createState() => _LiquidGlassControlState();
}

class _LiquidGlassControlState extends State<LiquidGlassControl>
    with SingleTickerProviderStateMixin {
  static const double _paintPadding = 40;

  late final GlassButtonController _motion;
  final FocusNode _focus = FocusNode(debugLabel: 'Liquid glass control');
  int? _pointer;

  @override
  void initState() {
    super.initState();
    _motion = GlassButtonController(vsync: this);
    _focus.addListener(_focusChanged);
  }

  @override
  void didChangeDependencies() {
    super.didChangeDependencies();
    _motion.setReducedMotion(MediaQuery.disableAnimationsOf(context));
  }

  void _focusChanged() {
    if (mounted) {
      setState(() {});
    }
  }

  @override
  void dispose() {
    _focus
      ..removeListener(_focusChanged)
      ..dispose();
    _motion.dispose();
    super.dispose();
  }

  @override
  Widget build(BuildContext context) {
    final boxSize = Size(
      widget.size.width + _paintPadding * 2,
      widget.size.height + _paintPadding * 2,
    );
    final baseRect = Rect.fromCenter(
      center: (Offset.zero & boxSize).center,
      width: widget.size.width,
      height: widget.size.height,
    );
    return AnimatedBuilder(
      animation: _motion,
      builder: (context, child) {
        final materialRect = LiquidShape.expandedRect(
          baseRect,
          press: _motion.press,
          tokens: widget.shapeTokens,
        );
        final path = GlassGeometryFrame.deformedCapsule(
          rect: materialRect,
          origin: _motion.pressOrigin == Offset.zero
              ? baseRect.center
              : _motion.pressOrigin,
          pull: _motion.displacement,
          velocity: _motion.displacement == Offset.zero
              ? Offset.zero
              : _motion.pointerVelocity,
          press: _motion.press,
        );
        final light = _motion.lightPosition == Offset.zero
            ? baseRect.center
            : _motion.lightPosition;
        final contentOffset = LiquidShape.contentOffset(
          displacement: _motion.displacement,
          velocity: _motion.pointerVelocity,
          press: _motion.press,
        );
        return MouseRegion(
          cursor: widget.onTap == null
              ? MouseCursor.defer
              : SystemMouseCursors.click,
          opaque: false,
          onHover: (event) => _motion.updateHover(event.localPosition),
          child: Listener(
            behavior: HitTestBehavior.opaque,
            onPointerDown: (event) {
              if (_pointer != null ||
                  !baseRect
                      .inflate(widget.hitSlop)
                      .contains(event.localPosition)) {
                return;
              }
              _pointer = event.pointer;
              _motion.beginPointer(
                position: event.localPosition,
                timestamp: event.timeStamp,
              );
            },
            onPointerMove: (event) {
              if (_pointer == event.pointer) {
                _motion.movePointer(
                  position: event.localPosition,
                  timestamp: event.timeStamp,
                );
              }
            },
            onPointerUp: (event) {
              if (_pointer != event.pointer) {
                return;
              }
              final inside = baseRect
                  .inflate(widget.hitSlop)
                  .contains(event.localPosition);
              _motion.endPointer();
              _pointer = null;
              if (inside) {
                widget.onTap?.call();
              }
            },
            onPointerCancel: (event) {
              if (_pointer == event.pointer) {
                _motion.cancelPointer();
                _pointer = null;
              }
            },
            child: Semantics(
              button: widget.onTap != null,
              label: widget.semanticsLabel,
              onTap: widget.onTap,
              child: Focus(
                focusNode: _focus,
                canRequestFocus: widget.onTap != null,
                onKeyEvent: (node, event) {
                  if (widget.onTap != null &&
                      event is KeyDownEvent &&
                      (event.logicalKey == LogicalKeyboardKey.enter ||
                          event.logicalKey == LogicalKeyboardKey.space)) {
                    widget.onTap?.call();
                    return KeyEventResult.handled;
                  }
                  return KeyEventResult.ignored;
                },
                child: SizedBox.fromSize(
                  size: boxSize,
                  child: Stack(
                    fit: StackFit.expand,
                    children: <Widget>[
                      GlassShell(
                        path: path,
                        glowCenter: light,
                        press: _motion.press,
                        focused: _focus.hasFocus,
                      ),
                      Center(
                        child: Transform.translate(
                          offset: contentOffset,
                          child: Transform.scale(
                            scale: LiquidShape.contentScale(_motion.press),
                            child: widget.child,
                          ),
                        ),
                      ),
                      const GlassTouchShield(),
                    ],
                  ),
                ),
              ),
            ),
          ),
        );
      },
    );
  }
}
