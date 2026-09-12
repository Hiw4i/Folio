import 'dart:math' as math;

import 'package:flutter/scheduler.dart';
import 'package:flutter/widgets.dart';

class GlassButtonController extends ChangeNotifier {
  GlassButtonController({TickerProvider? vsync}) {
    final ticker = vsync?.createTicker(_onTick);
    _ticker = ticker;
    ticker?.start();
  }

  static const double _fixedStep = 1 / 120;
  static const int _maxSubsteps = 4;
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

  Ticker? _ticker;
  Duration? _lastTick;
  double _accumulator = 0;
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
    displacement = _limit(displacement, _maxDrag);
    _wake();
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
    _wake();
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
    _dragTarget = _limit((position - _pointerStart) * _dragGain, _maxDrag);
    _wake();
    notifyListeners();
  }

  void endPointer() {
    if (!_pointerDown) {
      return;
    }
    _pointerDown = false;
    _dragTarget = Offset.zero;
    displacementVelocity += pointerVelocity * 0.11;
    _wake();
    notifyListeners();
  }

  void cancelPointer() {
    if (!_pointerDown) {
      return;
    }
    _pointerDown = false;
    _dragTarget = Offset.zero;
    _wake();
    notifyListeners();
  }

  void updateHover(Offset position) {
    if ((_lightTarget - position).distanceSquared < 0.01) {
      return;
    }
    _lightTarget = position;
    _wake();
  }

  void _wake() {
    _ticker?.muted = false;
  }

  bool _isAtRest() {
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

  @visibleForTesting
  void stepForTest(double seconds) {
    var remaining = seconds.clamp(0.0, 1.0);
    while (remaining > 0) {
      final step = math.min(_fixedStep, remaining);
      _step(step);
      remaining -= step;
    }
    notifyListeners();
  }

  void _onTick(Duration elapsed) {
    final previous = _lastTick;
    _lastTick = elapsed;
    if (previous == null) {
      return;
    }
    final frameDelta = math.min(
      (elapsed - previous).inMicroseconds / Duration.microsecondsPerSecond,
      1 / 30,
    );
    _accumulator += frameDelta;
    var steps = 0;
    while (_accumulator >= _fixedStep && steps < _maxSubsteps) {
      _step(_fixedStep);
      _accumulator -= _fixedStep;
      steps++;
    }
    if (steps == _maxSubsteps) {
      _accumulator = math.min(_accumulator, _fixedStep);
    }
    notifyListeners();
    if (_isAtRest()) {
      _ticker?.muted = true;
    }
  }

  void _step(double dt) {
    final nextPress = _springScalar(
      press,
      pressVelocity,
      _pointerDown ? 1 : 0,
      _pressSpring,
      dt,
    );
    press = nextPress.$1;
    pressVelocity = nextPress.$2;
    final nextDisplacement = _springOffset(
      displacement,
      displacementVelocity,
      _dragTarget,
      _returnSpring,
      dt,
    );
    displacement = nextDisplacement.$1;
    displacementVelocity = nextDisplacement.$2;
    displacement = _limit(displacement, _maxDrag);
    lightPosition = Offset.lerp(
      lightPosition,
      _lightTarget,
      1 - math.exp(-dt * 22),
    )!;
    press = press.clamp(0.0, 1.08);
  }

  static (double, double) _springScalar(
    double position,
    double velocity,
    double target,
    SpringDescription spring,
    double dt,
  ) {
    final acceleration =
        (spring.stiffness * (target - position) - spring.damping * velocity) /
        spring.mass;
    final nextVelocity = velocity + acceleration * dt;
    return (position + nextVelocity * dt, nextVelocity);
  }

  static (Offset, Offset) _springOffset(
    Offset position,
    Offset velocity,
    Offset target,
    SpringDescription spring,
    double dt,
  ) {
    final acceleration =
        (target - position) * (spring.stiffness / spring.mass) -
        velocity * (spring.damping / spring.mass);
    final nextVelocity = velocity + acceleration * dt;
    return (position + nextVelocity * dt, nextVelocity);
  }

  static Offset _limit(Offset value, double maximum) {
    if (value.distance <= maximum || value == Offset.zero) {
      return value;
    }
    return value / value.distance * maximum;
  }

  @override
  void dispose() {
    _ticker?.dispose();
    _ticker = null;
    super.dispose();
  }
}
