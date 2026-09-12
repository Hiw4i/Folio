import 'dart:math' as math;
import 'dart:ui' as ui;

import 'package:flutter/services.dart';
import 'package:flutter/widgets.dart';

import '../theme/folio_theme.dart';
import 'glass_geometry.dart';
import 'glass_shell.dart';
import 'liquid_segmented_controller.dart';

@immutable
class LiquidSegment<T> {
  const LiquidSegment({required this.value, required this.label});

  final T value;
  final String label;
}

class LiquidSegmentedControl<T> extends StatefulWidget {
  const LiquidSegmentedControl({
    required this.segments,
    required this.selected,
    required this.onSelected,
    super.key,
  });

  final List<LiquidSegment<T>> segments;
  final T selected;
  final ValueChanged<T> onSelected;

  @override
  State<LiquidSegmentedControl<T>> createState() =>
      _LiquidSegmentedControlState<T>();
}

class _LiquidSegmentedControlState<T> extends State<LiquidSegmentedControl<T>>
    with SingleTickerProviderStateMixin {
  static const double _height = 58;
  static const double _lensInset = 4;
  static final ui.ImageFilter _caseBlur = ui.ImageFilter.blur(
    sigmaX: 11,
    sigmaY: 11,
    tileMode: ui.TileMode.mirror,
  );

  late final LiquidSegmentedController _motion;
  int? _pointer;
  int? _focusedIndex;

  int get _selectedIndex {
    final index = widget.segments.indexWhere(
      (segment) => segment.value == widget.selected,
    );
    assert(index >= 0, 'selected must match one segment');
    return math.max(0, index);
  }

  @override
  void initState() {
    super.initState();
    assert(widget.segments.isNotEmpty);
    _motion = LiquidSegmentedController(
      initialIndex: _selectedIndex,
      itemCount: widget.segments.length,
      vsync: this,
    );
  }

  @override
  void didChangeDependencies() {
    super.didChangeDependencies();
    _motion.setReducedMotion(MediaQuery.disableAnimationsOf(context));
  }

  @override
  void didUpdateWidget(covariant LiquidSegmentedControl<T> oldWidget) {
    super.didUpdateWidget(oldWidget);
    assert(oldWidget.segments.length == widget.segments.length);
    if (oldWidget.selected != widget.selected) {
      _motion.select(_selectedIndex);
    }
  }

  void _select(int index) {
    _motion.select(index);
    widget.onSelected(widget.segments[index].value);
  }

  @override
  void dispose() {
    _motion.dispose();
    super.dispose();
  }

  @override
  Widget build(BuildContext context) {
    return SizedBox(
      height: _height,
      child: LayoutBuilder(
        builder: (context, constraints) {
          final size = Size(constraints.maxWidth, _height);
          return AnimatedBuilder(
            animation: _motion,
            builder: (context, child) {
              final segmentWidth = size.width / widget.segments.length;
              final centerX = segmentWidth * (_motion.position + 0.5);
              final baseWidth = segmentWidth - _lensInset * 2;
              final desiredWidth = baseWidth * (1 + _motion.stretch * 0.34);
              final availableHalfWidth = math.max(
                baseWidth / 2,
                math.min(centerX - 2, size.width - centerX - 2),
              );
              final lensWidth = math.min(desiredWidth, availableHalfWidth * 2);
              final lensHeight = 48 - _motion.stretch * 3.8;
              final lensRect = Rect.fromCenter(
                center: Offset(centerX, size.height / 2),
                width: lensWidth,
                height: lensHeight,
              );
              return MouseRegion(
                cursor: SystemMouseCursors.click,
                onHover: (event) => _motion.movePointer(event.localPosition),
                child: Listener(
                  behavior: HitTestBehavior.opaque,
                  onPointerDown: (event) {
                    if (_pointer != null) {
                      return;
                    }
                    _pointer = event.pointer;
                    _motion.beginPointer(event.localPosition);
                  },
                  onPointerMove: (event) {
                    if (_pointer == event.pointer) {
                      _motion.movePointer(event.localPosition);
                    }
                  },
                  onPointerUp: (event) {
                    if (_pointer == event.pointer) {
                      _pointer = null;
                      _motion.endPointer();
                    }
                  },
                  onPointerCancel: (event) {
                    if (_pointer == event.pointer) {
                      _pointer = null;
                      _motion.endPointer();
                    }
                  },
                  child: Stack(
                    clipBehavior: Clip.none,
                    children: <Widget>[
                      Positioned.fill(
                        child: ClipRRect(
                          borderRadius: BorderRadius.circular(_height / 2),
                          child: BackdropFilter(
                            filter: _caseBlur,
                            child: DecoratedBox(
                              decoration: BoxDecoration(
                                color: const Color(0x161A1B1D),
                                borderRadius: BorderRadius.circular(
                                  _height / 2,
                                ),
                                border: Border.all(
                                  color: const Color(0x22FFFFFF),
                                  width: 0.8,
                                ),
                              ),
                            ),
                          ),
                        ),
                      ),
                      _LiquidLens(
                        rect: lensRect,
                        motion: _motion,
                        focused: _focusedIndex != null,
                      ),
                      Positioned.fill(
                        child: Row(
                          children: <Widget>[
                            for (
                              var index = 0;
                              index < widget.segments.length;
                              index++
                            )
                              Expanded(
                                child: _SegmentLabel(
                                  label: widget.segments[index].label,
                                  selected:
                                      1 -
                                      (_motion.position - index).abs().clamp(
                                        0.0,
                                        1.0,
                                      ),
                                  onTap: () => _select(index),
                                  onFocusChanged: (focused) {
                                    setState(() {
                                      if (focused) {
                                        _focusedIndex = index;
                                      } else if (_focusedIndex == index) {
                                        _focusedIndex = null;
                                      }
                                    });
                                  },
                                ),
                              ),
                          ],
                        ),
                      ),
                    ],
                  ),
                ),
              );
            },
          );
        },
      ),
    );
  }
}

class _LiquidLens extends StatelessWidget {
  const _LiquidLens({
    required this.rect,
    required this.motion,
    required this.focused,
  });

  static const double _paintPadding = 34;
  final Rect rect;
  final LiquidSegmentedController motion;
  final bool focused;

  @override
  Widget build(BuildContext context) {
    final shellRect = rect.inflate(_paintPadding);
    final localRect = rect.shift(-shellRect.topLeft);
    final pointerInside = rect.inflate(8).contains(motion.lightPosition);
    final localPointer = pointerInside
        ? motion.lightPosition - shellRect.topLeft
        : localRect.center;
    final travelDirection = motion.velocity == 0 ? 0.0 : motion.velocity.sign;
    final deformation = Offset(
      travelDirection * motion.stretch * math.min(8, rect.width * 0.09),
      0,
    );
    final path = GlassGeometryFrame.deformedCapsule(
      rect: localRect,
      origin: localPointer,
      pull: deformation,
      velocity: Offset(motion.velocity * 70, 0),
      press: motion.press * (pointerInside ? 1 : 0.22),
    );
    return Positioned.fromRect(
      rect: shellRect,
      child: GlassShell(
        path: path,
        glowCenter: localPointer,
        press: motion.press * (pointerInside ? 1 : 0.22),
        focused: focused,
      ),
    );
  }
}

class _SegmentLabel extends StatelessWidget {
  const _SegmentLabel({
    required this.label,
    required this.selected,
    required this.onTap,
    required this.onFocusChanged,
  });

  final String label;
  final double selected;
  final VoidCallback onTap;
  final ValueChanged<bool> onFocusChanged;

  @override
  Widget build(BuildContext context) {
    final foreground = Color.lerp(
      FolioColors.textSecondary,
      FolioColors.textPrimary,
      selected,
    )!;
    return Semantics(
      button: true,
      selected: selected > 0.94,
      label: '$label documents',
      onTap: onTap,
      child: Focus(
        onFocusChange: onFocusChanged,
        onKeyEvent: (node, event) {
          if (event is KeyDownEvent &&
              (event.logicalKey == LogicalKeyboardKey.enter ||
                  event.logicalKey == LogicalKeyboardKey.space)) {
            onTap();
            return KeyEventResult.handled;
          }
          return KeyEventResult.ignored;
        },
        child: GestureDetector(
          behavior: HitTestBehavior.opaque,
          onTap: onTap,
          child: Center(
            child: Padding(
              padding: const EdgeInsets.symmetric(horizontal: 5),
              child: FittedBox(
                fit: BoxFit.scaleDown,
                child: Text(
                  label,
                  maxLines: 1,
                  style: TextStyle(
                    fontFamily: 'Inter',
                    color: foreground,
                    fontSize: 13.5,
                    fontWeight: selected > 0.58
                        ? FontWeight.w600
                        : FontWeight.w500,
                    letterSpacing: -0.12,
                  ),
                ),
              ),
            ),
          ),
        ),
      ),
    );
  }
}
