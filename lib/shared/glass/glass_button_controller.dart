import 'dart:math' as math;

import 'package:flutter/widgets.dart';

import 'liquid_motion_controller.dart';

class GlassButtonController extends LiquidMotionController {
  GlassButtonController({super.vsync});

  static const SpringDescription _pressSpring = SpringDescription(
    mass: 1,
    stiffness: 780,
    damping: 32,
  );
  static const SpringDescription _returnSpring = SpringDescription(
    mass: 0.92,
    stiffness: 560,
    damping: 22,
  );

  bool _pointerDown = false;
  double _maxDrag = 14;
  double _dragGain = 0.34;
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

  void setReducedMotion(bool reduced) {
    final maxDrag = reduced ? 4.0 : 14.0;
    final dragGain = reduced ? 0.12 : 0.34;
    if (maxDrag == _maxDrag && dragGain == _dragGain) {
      return;
    }
    _maxDrag = maxDrag;
    _dragGain = dragGain;
    displacement = LiquidSpring.limitOffset(displacement, _maxDrag);
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
      (position - _pointerStart) * _dragGain,
      _maxDrag,
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
    displacementVelocity += pointerVelocity * 0.11;
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
      spring: _pressSpring,
      dt: dt,
    );
    press = nextPress.$1;
    pressVelocity = nextPress.$2;
    final nextDisplacement = LiquidSpring.offset(
      position: displacement,
      velocity: displacementVelocity,
      target: _dragTarget,
      spring: _returnSpring,
      dt: dt,
    );
    displacement = nextDisplacement.$1;
    displacementVelocity = nextDisplacement.$2;
    displacement = LiquidSpring.limitOffset(displacement, _maxDrag);
    lightPosition = Offset.lerp(
      lightPosition,
      _lightTarget,
      1 - math.exp(-dt * 22),
    )!;
    press = press.clamp(0.0, 1.08);
  }
}
