import 'package:flutter/services.dart';
import 'package:flutter/widgets.dart';

import 'glass_button_controller.dart';
import 'glass_geometry.dart';
import 'glass_shell.dart';

class LiquidGlassButton extends StatefulWidget {
  const LiquidGlassButton({
    required this.label,
    required this.onTap,
    this.width = 168,
    this.height = 56,
    super.key,
  });

  final String label;
  final VoidCallback onTap;
  final double width;
  final double height;

  @override
  State<LiquidGlassButton> createState() => _LiquidGlassButtonState();
}

class _LiquidGlassButtonState extends State<LiquidGlassButton>
    with SingleTickerProviderStateMixin {
  static const double _pad = 40;

  late final GlassButtonController _motion;
  final FocusNode _focus = FocusNode(debugLabel: 'Glass button');
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
    final boxSize = Size(widget.width + _pad * 2, widget.height + _pad * 2);
    final capsule = Rect.fromCenter(
      center: (Offset.zero & boxSize).center,
      width: widget.width,
      height: widget.height,
    );
    return AnimatedBuilder(
      animation: _motion,
      builder: (context, child) {
        final path = GlassGeometryFrame.deformedCapsule(
          rect: capsule,
          origin: _motion.pressOrigin == Offset.zero
              ? capsule.center
              : _motion.pressOrigin,
          pull: _motion.displacement,
          velocity: _motion.displacement == Offset.zero
              ? Offset.zero
              : _motion.pointerVelocity,
          press: _motion.press,
        );
        final light = _motion.lightPosition == Offset.zero
            ? capsule.center
            : _motion.lightPosition;
        return MouseRegion(
          cursor: SystemMouseCursors.click,
          opaque: false,
          onHover: (event) => _motion.updateHover(event.localPosition),
          child: Listener(
            behavior: HitTestBehavior.translucent,
            onPointerDown: (event) {
              if (_pointer != null ||
                  !capsule.inflate(8).contains(event.localPosition)) {
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
              if (_pointer == event.pointer) {
                final inside = capsule.inflate(8).contains(event.localPosition);
                _motion.endPointer();
                _pointer = null;
                if (inside) {
                  widget.onTap();
                }
              }
            },
            onPointerCancel: (event) {
              if (_pointer == event.pointer) {
                _motion.cancelPointer();
                _pointer = null;
              }
            },
            child: Semantics(
              button: true,
              onTap: widget.onTap,
              child: Focus(
                focusNode: _focus,
                onKeyEvent: (node, event) {
                  if (event is KeyDownEvent &&
                      (event.logicalKey == LogicalKeyboardKey.enter ||
                          event.logicalKey == LogicalKeyboardKey.space)) {
                    widget.onTap();
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
                        child: Text(
                          widget.label,
                          maxLines: 1,
                          style: const TextStyle(
                            fontFamily: 'Inter',
                            color: Color(0xFFF4F3EF),
                            fontSize: 15,
                            fontWeight: FontWeight.w500,
                            letterSpacing: 0.1,
                          ),
                        ),
                      ),
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
