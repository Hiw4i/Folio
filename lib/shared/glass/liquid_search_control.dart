import 'package:flutter/foundation.dart';
import 'package:flutter/services.dart';
import 'package:flutter/widgets.dart';

import 'glass_geometry.dart';
import 'glass_motion_controller.dart';
import 'glass_tokens.dart';
import 'liquid_search_morph.dart';

class LiquidSearchControl extends StatefulWidget {
  const LiquidSearchControl({
    required this.onChanged,
    this.initialQuery = '',
    super.key,
  });

  final ValueChanged<String> onChanged;
  final String initialQuery;

  @override
  State<LiquidSearchControl> createState() => LiquidSearchControlState();
}

class LiquidSearchControlState extends State<LiquidSearchControl>
    with SingleTickerProviderStateMixin {
  static const double height = 176;
  static const GlassTokens _tokens = GlassTokens();

  late final GlassMotionController _motion;
  late final TextEditingController _searchController;
  final FocusNode _searchFocus = FocusNode(debugLabel: 'Search field');
  final FocusNode _mainFocus = FocusNode(debugLabel: 'Search button');
  final FocusNode _cancelFocus = FocusNode(debugLabel: 'Cancel button');
  int? _primaryPointer;
  bool _focusRequested = false;
  bool _reducedMotion = false;
  bool _wasExpanded = false;

  bool get isExpanded => _motion.wantsOpen || _motion.morph > 0.02;

  void open() => _motion.requestOpen();

  @override
  void initState() {
    super.initState();
    _searchController = TextEditingController(text: widget.initialQuery)
      ..addListener(_queryChanged);
    _motion = GlassMotionController(vsync: this)..addListener(_syncFocus);
    _searchFocus.addListener(_focusChanged);
    _mainFocus.addListener(_focusChanged);
    _cancelFocus.addListener(_focusChanged);
  }

  @override
  void didChangeDependencies() {
    super.didChangeDependencies();
    final reducedMotion = MediaQuery.disableAnimationsOf(context);
    if (reducedMotion != _reducedMotion) {
      _reducedMotion = reducedMotion;
      _motion.setReducedMotion(reducedMotion);
    }
  }

  void _queryChanged() {
    widget.onChanged(_searchController.text);
  }

  void _focusChanged() {
    if (mounted) {
      setState(() {});
    }
  }

  void _syncFocus() {
    if (_motion.wantsOpen && _motion.morph > 0.78 && !_focusRequested) {
      _focusRequested = true;
      _wasExpanded = true;
      _searchFocus.requestFocus();
    }
    if (!_motion.wantsOpen && _motion.morph < 0.62 && _focusRequested) {
      _focusRequested = false;
      _searchFocus.unfocus();
      _cancelFocus.unfocus();
      if (defaultTargetPlatform == TargetPlatform.windows) {
        _mainFocus.requestFocus();
      }
    }
    if (_wasExpanded &&
        _motion.state == GlassInteractionState.idle &&
        _searchController.text.isNotEmpty) {
      _wasExpanded = false;
      _searchController.clear();
    }
  }

  void close() {
    if (_motion.morph > 0.02 || _motion.wantsOpen) {
      _motion.requestClose();
    }
  }

  void _handleBack() {
    if (_searchFocus.hasFocus) {
      _searchFocus.unfocus();
      return;
    }
    close();
  }

  @override
  void dispose() {
    _motion
      ..removeListener(_syncFocus)
      ..dispose();
    _searchController
      ..removeListener(_queryChanged)
      ..dispose();
    _searchFocus.dispose();
    _mainFocus.dispose();
    _cancelFocus.dispose();
    super.dispose();
  }

  @override
  Widget build(BuildContext context) {
    return CallbackShortcuts(
      bindings: <ShortcutActivator, VoidCallback>{
        const SingleActivator(LogicalKeyboardKey.escape): close,
      },
      child: FocusTraversalGroup(
        child: AnimatedBuilder(
          animation: _motion,
          builder: (context, child) {
            final collapsed = !_motion.wantsOpen && _motion.morph < 0.02;
            return PopScope<void>(
              canPop: collapsed,
              onPopInvokedWithResult: (didPop, result) {
                if (!didPop && !collapsed) {
                  _handleBack();
                }
              },
              child: child!,
            );
          },
          child: LayoutBuilder(
            builder: (context, constraints) {
              final size = constraints.biggest;
              final bottomPadding = MediaQuery.viewPaddingOf(context).bottom;
              final centerY = size.height - bottomPadding - 52;
              return AnimatedBuilder(
                animation: _motion,
                builder: (context, child) {
                  final cancelOwnsDisplacement =
                      _motion.materialTarget == GlassPointerTarget.cancel;
                  final frame = GlassGeometry.resolve(
                    viewport: size,
                    morph: _motion.morph,
                    separation: _motion.separation,
                    displacement: cancelOwnsDisplacement
                        ? Offset.zero
                        : _motion.displacement,
                    cancelDisplacement: cancelOwnsDisplacement
                        ? _motion.displacement
                        : Offset.zero,
                    pointerPosition: _motion.lightPosition,
                    press: _motion.press,
                    pointerVelocity: _motion.pointerVelocity,
                    settleWobble: _motion.settleWobble,
                    deformCancel:
                        _motion.materialTarget == GlassPointerTarget.cancel,
                    collapsedCenter: Offset(
                      size.width - _tokens.horizontalMargin - 34,
                      centerY,
                    ),
                    expandedGroupLeft: _tokens.horizontalMargin,
                    centerY: centerY,
                  );
                  return MouseRegion(
                    onHover: (event) =>
                        _motion.updateHover(event.localPosition),
                    child: Listener(
                      behavior: HitTestBehavior.translucent,
                      onPointerDown: (event) {
                        if (_primaryPointer != null) {
                          return;
                        }
                        final target = frame.hitCancel(event.localPosition)
                            ? GlassPointerTarget.cancel
                            : frame.hitMain(event.localPosition)
                            ? GlassPointerTarget.main
                            : GlassPointerTarget.none;
                        if (target == GlassPointerTarget.none) {
                          return;
                        }
                        if (target == GlassPointerTarget.main &&
                            frame.morph < 0.68) {
                          _mainFocus.requestFocus();
                        }
                        _primaryPointer = event.pointer;
                        _motion.beginPointer(
                          position: event.localPosition,
                          timestamp: event.timeStamp,
                          target: target,
                        );
                      },
                      onPointerMove: (event) {
                        if (_primaryPointer == event.pointer) {
                          _motion.movePointer(
                            position: event.localPosition,
                            timestamp: event.timeStamp,
                          );
                        }
                      },
                      onPointerUp: (event) {
                        if (_primaryPointer == event.pointer) {
                          _motion.endPointer(
                            position: event.localPosition,
                            timestamp: event.timeStamp,
                          );
                          _primaryPointer = null;
                        }
                      },
                      onPointerCancel: (event) {
                        if (_primaryPointer == event.pointer) {
                          _motion.cancelPointer();
                          _primaryPointer = null;
                        }
                      },
                      child: RepaintBoundary(
                        child: LiquidSearchMorph(
                          frame: frame,
                          motion: _motion,
                          searchController: _searchController,
                          searchFocus: _searchFocus,
                          mainFocus: _mainFocus,
                          cancelFocus: _cancelFocus,
                          reducedMotion: _reducedMotion,
                        ),
                      ),
                    ),
                  );
                },
              );
            },
          ),
        ),
      ),
    );
  }
}
