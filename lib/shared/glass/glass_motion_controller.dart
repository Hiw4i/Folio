import 'dart:math' as math;

import 'package:flutter/scheduler.dart';
import 'package:flutter/widgets.dart';

import 'glass_tokens.dart';

enum GlassInteractionState { idle, pressed, dragging, opening, open, closing }

enum GlassPointerTarget { none, main, cancel }

class GlassMotionController extends ChangeNotifier {
  GlassMotionController({TickerProvider? vsync, MotionTokens? tokens})
    : _tokens = tokens ?? const MotionTokens.standard() {
    final ticker = vsync?.createTicker(_onTick);
    _ticker = ticker;
    ticker?.start();
  }

  static const double _fixedStep = 1 / 120;
  static const int _maxSubsteps = 4;

  Ticker? _ticker;
  MotionTokens _tokens;
  Duration? _lastTick;
  double _accumulator = 0;
  bool _wantsOpen = false;
  bool _pointerDown = false;
  bool _dragExceeded = false;
  bool _collapseImpulseArmed = false;
  bool _openingImpulseArmed = false;
  GlassPointerTarget _activeTarget = GlassPointerTarget.none;
  GlassPointerTarget _materialTarget = GlassPointerTarget.none;
  Offset _pointerStart = Offset.zero;
  Offset _lastPointer = Offset.zero;
  Duration _lastPointerTime = Duration.zero;
  Offset _dragTarget = Offset.zero;
  Offset _lightTarget = Offset.zero;

  GlassInteractionState state = GlassInteractionState.idle;
  double morph = 0;
  double morphVelocity = 0;
  double separation = 0;
  double separationVelocity = 0;
  double press = 0;
  double pressVelocity = 0;
  double submitEnergy = 0;
  double submitVelocity = 0;
  double settleWobble = 0;
  double settleWobbleVelocity = 0;
  Offset displacement = Offset.zero;
  Offset displacementVelocity = Offset.zero;
  Offset pointerVelocity = Offset.zero;
  Offset lightPosition = Offset.zero;

  bool get wantsOpen => _wantsOpen;
  bool get isOpen => state == GlassInteractionState.open;
  bool get isPointerDown => _pointerDown;
  GlassPointerTarget get activeTarget => _activeTarget;
  GlassPointerTarget get materialTarget => _materialTarget;
  MotionTokens get tokens => _tokens;

  void _wake() {
    _ticker?.muted = false;
  }

  bool _isAtRest() {
    if (_pointerDown) {
      return false;
    }
    final parked = _wantsOpen
        ? state == GlassInteractionState.open
        : state == GlassInteractionState.idle;
    if (!parked) {
      return false;
    }
    if (press > 0.01 || submitEnergy > 0.005) {
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

  void setReducedMotion(bool reduced) {
    final next = reduced
        ? const MotionTokens.reduced()
        : const MotionTokens.standard();
    if (next.maxDrag == _tokens.maxDrag) {
      return;
    }
    _tokens = next;
    displacement = _limit(displacement, _tokens.maxDrag);
    _wake();
    notifyListeners();
  }

  void beginPointer({
    required Offset position,
    required Duration timestamp,
    required GlassPointerTarget target,
  }) {
    if (_pointerDown || target == GlassPointerTarget.none) {
      return;
    }
    _pointerDown = true;
    _dragExceeded = false;
    _activeTarget = target;
    _materialTarget = target;
    _pointerStart = position;
    _lastPointer = position;
    _lastPointerTime = timestamp;
    _lightTarget = position;
    pointerVelocity = Offset.zero;
    if (!_wantsOpen && morph < 0.08 && target == GlassPointerTarget.main) {
      state = GlassInteractionState.pressed;
    }
    _wake();
    notifyListeners();
  }

  void movePointer({required Offset position, required Duration timestamp}) {
    _lightTarget = position;
    if (!_pointerDown) {
      notifyListeners();
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

    final travel = position - _pointerStart;
    if (travel.distance > _tokens.tapSlop) {
      _dragExceeded = true;
      if (!_wantsOpen && _activeTarget == GlassPointerTarget.main) {
        state = GlassInteractionState.dragging;
      }
    }
    if (_dragExceeded && _activeTarget == GlassPointerTarget.main) {
      _dragTarget = _limit(travel * _tokens.dragGain, _tokens.maxDrag);
    } else if (_dragExceeded && _activeTarget == GlassPointerTarget.cancel) {
      _dragTarget = _limit(travel * 0.32, 12);
    }
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

  void endPointer({required Offset position, required Duration timestamp}) {
    if (!_pointerDown) {
      return;
    }
    movePointer(position: position, timestamp: timestamp);
    final wasTap = !_dragExceeded;
    final target = _activeTarget;
    _pointerDown = false;
    _activeTarget = GlassPointerTarget.none;
    _dragTarget = Offset.zero;
    displacementVelocity += pointerVelocity * _tokens.velocityGain;

    if (wasTap && target == GlassPointerTarget.cancel && separation > 0.82) {
      requestClose();
    } else if (wasTap && target == GlassPointerTarget.main) {
      if (!_wantsOpen || state == GlassInteractionState.closing) {
        requestOpen();
      }
    } else if (!_wantsOpen) {
      state = GlassInteractionState.idle;
    }
    _wake();
    notifyListeners();
  }

  void cancelPointer() {
    if (!_pointerDown) {
      return;
    }
    _pointerDown = false;
    _dragExceeded = true;
    _activeTarget = GlassPointerTarget.none;
    _dragTarget = Offset.zero;
    if (!_wantsOpen && morph < 0.08) {
      state = GlassInteractionState.idle;
    }
    _wake();
    notifyListeners();
  }

  void requestOpen() {
    _openingImpulseArmed = morph < 0.94 || separation < 0.92;
    _wantsOpen = true;
    _collapseImpulseArmed = false;
    state = GlassInteractionState.opening;
    _wake();
    notifyListeners();
  }

  void requestClose() {
    _wantsOpen = false;
    _openingImpulseArmed = false;
    _collapseImpulseArmed = morph > 0.18;
    state = GlassInteractionState.closing;
    _wake();
    notifyListeners();
  }

  void submit() {
    if (morph < 0.78) {
      return;
    }
    submitEnergy = 1;
    submitVelocity = 0;
    _wake();
    notifyListeners();
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
    final previousMorph = morph;
    final previousSeparation = separation;
    final morphTarget = _wantsOpen
        ? 1.0
        : separation < 0.30
        ? 0.0
        : 1.0;
    final separationTarget = _wantsOpen && morph > 0.28 ? 1.0 : 0.0;

    final nextMorph = _springScalar(
      morph,
      morphVelocity,
      morphTarget,
      _tokens.morph,
      dt,
    );
    morph = nextMorph.$1;
    morphVelocity = nextMorph.$2;
    final nextSeparation = _springScalar(
      separation,
      separationVelocity,
      separationTarget,
      _tokens.separation,
      dt,
    );
    separation = nextSeparation.$1;
    separationVelocity = nextSeparation.$2;
    if (_wantsOpen &&
        _openingImpulseArmed &&
        previousSeparation < 0.92 &&
        separation >= 0.92 &&
        morph > 0.90) {
      settleWobbleVelocity += _tokens.maxDrag > 10 ? 132 : 20;
      _openingImpulseArmed = false;
    }
    final nextPress = _springScalar(
      press,
      pressVelocity,
      _pointerDown ? 1 : 0,
      _tokens.press,
      dt,
    );
    press = nextPress.$1;
    pressVelocity = nextPress.$2;
    final nextSubmit = _springScalar(
      submitEnergy,
      submitVelocity,
      0,
      const SpringDescription(mass: 1, stiffness: 250, damping: 19),
      dt,
    );
    submitEnergy = nextSubmit.$1;
    submitVelocity = nextSubmit.$2;
    if (!_wantsOpen &&
        _collapseImpulseArmed &&
        previousMorph > 0.16 &&
        morph <= 0.16 &&
        separation < 0.10) {
      settleWobbleVelocity += _tokens.maxDrag > 10 ? 136 : 22;
      _collapseImpulseArmed = false;
    }
    final nextSettleWobble = _springScalar(
      settleWobble,
      settleWobbleVelocity,
      0,
      const SpringDescription(mass: 1, stiffness: 250, damping: 9.6),
      dt,
    );
    settleWobble = nextSettleWobble.$1.clamp(-10.5, 10.5);
    settleWobbleVelocity = nextSettleWobble.$2;
    final nextDisplacement = _springOffset(
      displacement,
      displacementVelocity,
      _dragTarget,
      _tokens.pointerReturn,
      dt,
    );
    displacement = nextDisplacement.$1;
    displacementVelocity = nextDisplacement.$2;
    displacement = _limit(displacement, _tokens.maxDrag);
    lightPosition = Offset.lerp(
      lightPosition,
      _lightTarget,
      1 - math.exp(-dt * 22),
    )!;

    morph = morph.clamp(-0.035, 1.065);
    separation = separation.clamp(-0.035, 1.055);
    press = press.clamp(0.0, 1.08);
    submitEnergy = submitEnergy.clamp(0.0, 1.0);
    if (!_pointerDown &&
        press < 0.01 &&
        displacement.distance < 0.08 &&
        displacementVelocity.distance < 0.8) {
      _materialTarget = GlassPointerTarget.none;
    }

    if (_wantsOpen) {
      state =
          (_isClose(morph, 1) &&
              morphVelocity.abs() < 0.015 &&
              _isClose(separation, 1) &&
              separationVelocity.abs() < 0.015)
          ? GlassInteractionState.open
          : GlassInteractionState.opening;
    } else if (!_pointerDown &&
        _isClose(morph, 0) &&
        morphVelocity.abs() < 0.015 &&
        _isClose(separation, 0) &&
        separationVelocity.abs() < 0.015 &&
        settleWobble.abs() < 0.02 &&
        settleWobbleVelocity.abs() < 0.15) {
      state = GlassInteractionState.idle;
    } else if (!_pointerDown || morph > 0.08) {
      state = GlassInteractionState.closing;
    }
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

  static bool _isClose(double value, double target) =>
      (value - target).abs() < 0.002;

  @override
  void dispose() {
    _ticker?.dispose();
    _ticker = null;
    super.dispose();
  }
}
