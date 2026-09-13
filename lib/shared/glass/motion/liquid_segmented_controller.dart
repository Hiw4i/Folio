import 'dart:math' as math;

import 'package:flutter/widgets.dart';

import 'glass_tokens.dart';
import 'liquid_motion_controller.dart';

class LiquidSegmentedController extends LiquidMotionController {
  LiquidSegmentedController({
    required int initialIndex,
    required int itemCount,
    super.vsync,
  }) : assert(itemCount > 0),
       assert(initialIndex >= 0 && initialIndex < itemCount),
       _itemCount = itemCount,
       position = initialIndex.toDouble(),
       _target = initialIndex.toDouble();

  static const SpringDescription _stretchSpring = SpringDescription(
    mass: 0.86,
    stiffness: 250,
    damping: 18,
  );
  static const SpringDescription _dragSpring = SpringDescription(
    mass: 0.74,
    stiffness: 520,
    damping: 28,
  );

  final int _itemCount;
  MotionTokens _tokens = const MotionTokens.standard();
  double _target;
  bool _pointerDown = false;
  bool _draggingLens = false;
  double _maximumStretch = 1;
  double _dragGrabOffset = 0;
  double _pointerSpeed = 0;
  double _lastPointerX = 0;
  Duration _lastPointerTime = Duration.zero;
  Offset _lightTarget = Offset.zero;

  double position;
  double velocity = 0;
  double stretch = 0;
  double stretchVelocity = 0;
  double press = 0;
  double pressVelocity = 0;
  Offset lightPosition = Offset.zero;

  int get targetIndex => _target.round().clamp(0, _itemCount - 1);
  bool get isPointerDown => _pointerDown;
  bool get isDraggingLens => _draggingLens;

  void setReducedMotion(bool reduced) {
    final next = reduced
        ? const MotionTokens.reduced()
        : const MotionTokens.standard();
    final maximumStretch = reduced ? 0.08 : 1.0;
    if (_tokens.maxDrag == next.maxDrag && _maximumStretch == maximumStretch) {
      return;
    }
    _tokens = next;
    _maximumStretch = maximumStretch;
    stretch = math.min(stretch, maximumStretch);
    wake();
    notifyListeners();
  }

  void select(int index) {
    assert(index >= 0 && index < _itemCount);
    _selectTarget(index.toDouble(), addImpulse: true);
  }

  void beginPointer({
    required Offset position,
    required Duration timestamp,
    required double itemExtent,
    required bool dragLens,
  }) {
    if (_pointerDown || itemExtent <= 0) {
      return;
    }
    _pointerDown = true;
    _draggingLens = dragLens;
    _lightTarget = position;
    _lastPointerX = position.dx;
    _lastPointerTime = timestamp;
    _pointerSpeed = 0;
    if (dragLens) {
      final pointerPosition = position.dx / itemExtent - 0.5;
      _dragGrabOffset = pointerPosition - this.position;
      _target = this.position.clamp(0.0, _itemCount - 1.0);
    }
    wake();
    notifyListeners();
  }

  void movePointer({
    required Offset position,
    required Duration timestamp,
    required double itemExtent,
  }) {
    _lightTarget = position;
    if (!_pointerDown || itemExtent <= 0) {
      wake();
      return;
    }
    final elapsedMicros = (timestamp - _lastPointerTime).inMicroseconds.clamp(
      1000,
      100000,
    );
    final seconds = elapsedMicros / Duration.microsecondsPerSecond;
    final rawSpeed = (position.dx - _lastPointerX) / itemExtent / seconds;
    _pointerSpeed = _pointerSpeed * 0.56 + rawSpeed * 0.44;
    _lastPointerX = position.dx;
    _lastPointerTime = timestamp;

    if (_draggingLens) {
      final pointerPosition = position.dx / itemExtent - 0.5;
      _selectTarget(pointerPosition - _dragGrabOffset, addImpulse: false);
    }
    wake();
    notifyListeners();
  }

  int endPointer({
    required Offset position,
    required Duration timestamp,
    required double itemExtent,
  }) {
    if (!_pointerDown) {
      return targetIndex;
    }
    movePointer(
      position: position,
      timestamp: timestamp,
      itemExtent: itemExtent,
    );
    final projected = _draggingLens
        ? _target + _pointerSpeed.clamp(-12.0, 12.0) * 0.025
        : position.dx / itemExtent - 0.5;
    final selected = projected.round().clamp(0, _itemCount - 1);
    _pointerDown = false;
    _draggingLens = false;
    _selectTarget(selected.toDouble(), addImpulse: true);
    wake();
    notifyListeners();
    return selected;
  }

  void cancelPointer(int selectedIndex) {
    if (!_pointerDown) {
      return;
    }
    _pointerDown = false;
    _draggingLens = false;
    _pointerSpeed = 0;
    _selectTarget(selectedIndex.toDouble(), addImpulse: false);
    wake();
    notifyListeners();
  }

  void updateHover(Offset position) {
    _lightTarget = position;
    wake();
  }

  void _selectTarget(double target, {required bool addImpulse}) {
    final nextTarget = target.clamp(0.0, _itemCount - 1.0);
    if ((_target - nextTarget).abs() < 0.001) {
      return;
    }
    final travel = (nextTarget - position).abs();
    _target = nextTarget;
    if (addImpulse && _maximumStretch > 0.1) {
      stretchVelocity += math.min(7.5, 1.8 + travel * 1.15);
    }
    wake();
  }

  @override
  bool get isAtRest =>
      (position - _target).abs() < 0.001 &&
      velocity.abs() < 0.01 &&
      stretch < 0.002 &&
      stretchVelocity.abs() < 0.01 &&
      press < 0.002 &&
      pressVelocity.abs() < 0.01 &&
      (!_pointerDown && (lightPosition - _lightTarget).distance < 0.05);

  @override
  void integrate(double dt) {
    final movement = LiquidSpring.scalar(
      position: position,
      velocity: velocity,
      target: _target,
      spring: _draggingLens && _maximumStretch > 0.1
          ? _dragSpring
          : _tokens.separation,
      dt: dt,
    );
    position = movement.$1.clamp(-0.08, _itemCount - 0.92);
    velocity = movement.$2;

    final distance = (_target - position).abs();
    final pointerStretch = (_pointerSpeed.abs() * 0.045).clamp(0.0, 1.0);
    final dynamicStretch =
        math.max(
          (distance * 0.34 + velocity.abs() * 0.055).clamp(0.0, 1.0),
          _draggingLens ? pointerStretch : 0,
        ) *
        _maximumStretch;
    final stretching = LiquidSpring.scalar(
      position: stretch,
      velocity: stretchVelocity,
      target: dynamicStretch,
      spring: _stretchSpring,
      dt: dt,
    );
    stretch = stretching.$1.clamp(0.0, _maximumStretch * 1.08);
    stretchVelocity = stretching.$2;

    final pressing = LiquidSpring.scalar(
      position: press,
      velocity: pressVelocity,
      target: _pointerDown ? 1 : 0,
      spring: _tokens.press,
      dt: dt,
    );
    press = pressing.$1.clamp(0.0, 1.08);
    pressVelocity = pressing.$2;
    lightPosition = Offset.lerp(
      lightPosition,
      _lightTarget,
      1 - math.exp(-dt * 22),
    )!;
    _pointerSpeed *= math.exp(-dt * 11);
  }
}
