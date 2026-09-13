import 'dart:math' as math;

import 'package:flutter/widgets.dart';

import 'glass_tokens.dart';
import 'liquid_motion_controller.dart';

/// Button-press driver tuned to the search reference ([MotionTokens.standard]).
///
/// Shares press/return springs, drag gain, max drag and release impulse with
/// [GlassMotionController] so every liquid surface stretches identically.
class GlassButtonController extends LiquidMotionController {
  GlassButtonController({super.vsync, MotionTokens? tokens})
    : _tokens = tokens ?? const MotionTokens.standard();

  MotionTokens _tokens;

  bool _pointerDown = false;
  Offset _pointerStart = Offset.zero;
  Offset _lastPointer = Offset.zero;
  Duration _lastPointerTime = Duration.zero;
  Offset _dragTarget = Offset.zero;
  Offset _lightTarget = Offset.zero;

  double press = 0;
  double pressVelocity = 0;
  Offset displacement = Offset.zero;
  Offset displacementVelocity = Offset.zero;
  Offset pointerVelocity = Offset.zero;
  Offset lightPosition = Offset.zero;
  Offset pressOrigin = Offset.zero;

  bool get isPointerDown => _pointerDown;

  MotionTokens get tokens => _tokens;

  void setReducedMotion(bool reduced) {
    final next = reduced
        ? const MotionTokens.reduced()
        : const MotionTokens.standard();
    if (next.maxDrag == _tokens.maxDrag &&
        next.dragGain == _tokens.dragGain &&
        next.velocityGain == _tokens.velocityGain) {
      return;
    }
    _tokens = next;
    displacement = LiquidSpring.limitOffset(displacement, _tokens.maxDrag);
    wake();
    notifyListeners();
  }

  void beginPointer({required Offset position, required Duration timestamp}) {
    if (_pointerDown) {
      return;
    }
    _pointerDown = true;
    _pointerStart = position;
    _lastPointer = position;
    _lastPointerTime = timestamp;
    _lightTarget = position;
    pressOrigin = position;
    pointerVelocity = Offset.zero;
    wake();
    notifyListeners();
  }

  void movePointer({required Offset position, required Duration timestamp}) {
    _lightTarget = position;
    if (!_pointerDown) {
      return;
    }
    final elapsedMicros = (timestamp - _lastPointerTime).inMicroseconds.clamp(
      1000,
      100000,
    );
    final dt = elapsedMicros / Duration.microsecondsPerSecond;
    final rawVelocity = (position - _lastPointer) / dt;
    pointerVelocity = Offset.lerp(pointerVelocity, rawVelocity, 0.38)!;
    _lastPointer = position;
    _lastPointerTime = timestamp;
    _dragTarget = LiquidSpring.limitOffset(
      (position - _pointerStart) * _tokens.dragGain,
      _tokens.maxDrag,
    );
    wake();
    notifyListeners();
  }

  void endPointer() {
    if (!_pointerDown) {
      return;
    }
    _pointerDown = false;
    _dragTarget = Offset.zero;
    displacementVelocity += pointerVelocity * _tokens.velocityGain;
    wake();
    notifyListeners();
  }

  void cancelPointer() {
    if (!_pointerDown) {
      return;
    }
    _pointerDown = false;
    _dragTarget = Offset.zero;
    wake();
    notifyListeners();
  }

  void updateHover(Offset position) {
    if ((_lightTarget - position).distanceSquared < 0.01) {
      return;
    }
    _lightTarget = position;
    wake();
  }

  @override
  bool get isAtRest {
    if (_pointerDown) {
      return false;
    }
    if (press > 0.01 || pressVelocity.abs() > 0.05) {
      return false;
    }
    if (displacement.distance > 0.08 || displacementVelocity.distance > 0.8) {
      return false;
    }
    if ((lightPosition - _lightTarget).distance > 0.05) {
      return false;
    }
    return true;
  }

  @override
  void integrate(double dt) {
    final nextPress = LiquidSpring.scalar(
      position: press,
      velocity: pressVelocity,
      target: _pointerDown ? 1 : 0,
      spring: _tokens.press,
      dt: dt,
    );
    press = nextPress.$1;
    pressVelocity = nextPress.$2;
    final nextDisplacement = LiquidSpring.offset(
      position: displacement,
      velocity: displacementVelocity,
      target: _dragTarget,
      spring: _tokens.pointerReturn,
      dt: dt,
    );
    displacement = nextDisplacement.$1;
    displacementVelocity = nextDisplacement.$2;
    displacement = LiquidSpring.limitOffset(displacement, _tokens.maxDrag);
    lightPosition = Offset.lerp(
      lightPosition,
      _lightTarget,
      1 - math.exp(-dt * 22),
    )!;
    press = press.clamp(0.0, 1.08);
  }
}
