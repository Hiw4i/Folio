import 'dart:math' as math;

import 'package:flutter/widgets.dart';

import 'glass_tokens.dart';

@immutable
class GlassGeometryFrame {
  GlassGeometryFrame({
    required this.mainRect,
    required this.cancelRect,
    required this.opticalBounds,
    required this.neckRect,
    required this.neckRadius,
    required this.morph,
    required this.separation,
    required this.cancelVisible,
    required this.cancelInteractive,
    required this.iconCenter,
    required this.deformationOrigin,
    required this.mainDeformation,
    required this.cancelDeformation,
    required this.deformationVelocity,
    required this.press,
    required this.deformCancel,
  });

  final Rect mainRect;
  final Rect cancelRect;
  final Rect opticalBounds;
  final Rect neckRect;
  final double neckRadius;
  final double morph;
  final double separation;
  final bool cancelVisible;
  final bool cancelInteractive;
  final Offset iconCenter;
  final Offset deformationOrigin;
  final Offset mainDeformation;
  final Offset cancelDeformation;
  final Offset deformationVelocity;
  final double press;
  final bool deformCancel;
  late final Path _localUnifiedPath = _createLocalUnifiedPath();

  Rect get localMainRect => mainRect.shift(-opticalBounds.topLeft);
  Rect get localCancelRect => cancelRect.shift(-opticalBounds.topLeft);

  bool hitMain(Offset position) => mainRect.inflate(8).contains(position);

  bool hitCancel(Offset position) =>
      cancelInteractive && cancelRect.inflate(6).contains(position);

  Path buildLocalUnifiedPath() => _localUnifiedPath;

  Path _createLocalUnifiedPath() {
    final localOrigin = deformationOrigin - opticalBounds.topLeft;
    var result = GlassGeometryFrame.deformedCapsule(
      rect: localMainRect,
      origin: localOrigin,
      pull: mainDeformation,
      velocity: mainDeformation == Offset.zero
          ? Offset.zero
          : deformationVelocity,
      press: deformCancel ? 0 : press,
    );
    if (!cancelVisible) {
      return result;
    }
    final cancelPath = GlassGeometryFrame.deformedCapsule(
      rect: localCancelRect,
      origin: localOrigin,
      pull: cancelDeformation,
      velocity: cancelDeformation == Offset.zero
          ? Offset.zero
          : deformationVelocity,
      press: deformCancel ? press : 0,
    );
    result = Path.combine(PathOperation.union, result, cancelPath);
    if (neckRadius > 0.5) {
      final bridge = _bridgePath(
        localMainRect.right - 3,
        localCancelRect.left + 3,
        localMainRect.center.dy,
        neckRadius,
      );
      if (bridge != null) {
        result = Path.combine(PathOperation.union, result, bridge);
      }
    }
    return result;
  }

  static Path? _bridgePath(
    double x0,
    double x1,
    double centerY,
    double endHalf,
  ) {
    final gap = x1 - x0;
    if (gap <= 0 || endHalf <= 0.5) {
      return null;
    }
    final depth = 0.30 + 0.25 * (gap / 20).clamp(0.0, 1.0);
    double half(double t) => endHalf * (1 - depth * math.sin(math.pi * t));
    const steps = 12;
    final outline = <Offset>[];
    for (var i = 0; i <= steps; i++) {
      final t = i / steps;
      outline.add(Offset(x0 + gap * t, centerY - half(t)));
    }
    for (var i = steps; i >= 0; i--) {
      final t = i / steps;
      outline.add(Offset(x0 + gap * t, centerY + half(t)));
    }
    final path = Path()..moveTo(outline.first.dx, outline.first.dy);
    for (var index = 0; index < outline.length; index++) {
      final p0 = outline[(index - 1 + outline.length) % outline.length];
      final p1 = outline[index];
      final p2 = outline[(index + 1) % outline.length];
      final p3 = outline[(index + 2) % outline.length];
      final control1 = p1 + (p2 - p0) / 6;
      final control2 = p2 - (p3 - p1) / 6;
      path.cubicTo(
        control1.dx,
        control1.dy,
        control2.dx,
        control2.dy,
        p2.dx,
        p2.dy,
      );
    }
    return path..close();
  }

  static Path deformedCapsule({
    required Rect rect,
    required Offset origin,
    Offset pull = Offset.zero,
    Offset velocity = Offset.zero,
    double press = 0,
  }) {
    if (pull.distanceSquared < 0.0001 && press < 0.001) {
      return Path()..addRRect(
        RRect.fromRectAndRadius(rect, Radius.circular(rect.height / 2)),
      );
    }

    final radius = rect.height / 2;
    final points = <Offset>[];
    const arcSteps = 10;
    const lineSteps = 8;

    void addLine(Offset from, Offset to) {
      if ((to - from).distanceSquared < 0.01) {
        return;
      }
      for (var index = 0; index < lineSteps; index++) {
        points.add(Offset.lerp(from, to, index / lineSteps)!);
      }
    }

    void addArc(Offset center, double startAngle) {
      for (var index = 0; index < arcSteps; index++) {
        final angle = startAngle + index / arcSteps * math.pi / 2;
        points.add(center + Offset(math.cos(angle), math.sin(angle)) * radius);
      }
    }

    addLine(
      Offset(rect.left + radius, rect.top),
      Offset(rect.right - radius, rect.top),
    );
    addArc(Offset(rect.right - radius, rect.top + radius), -math.pi / 2);
    addArc(Offset(rect.right - radius, rect.bottom - radius), 0);
    addLine(
      Offset(rect.right - radius, rect.bottom),
      Offset(rect.left + radius, rect.bottom),
    );
    addArc(Offset(rect.left + radius, rect.bottom - radius), math.pi / 2);
    addArc(Offset(rect.left + radius, rect.top + radius), math.pi);

    final sigma = math.max(
      rect.height * 0.82,
      math.min(rect.width * 0.335, 134.0),
    );
    final velocityPull = _limit(velocity * 0.0014 * press, 4.0);
    final totalPull = pull + velocityPull;
    final deformed = <Offset>[
      for (final point in points)
        _deformPoint(point, rect, origin, totalPull, sigma, press),
    ];

    final path = Path()..moveTo(deformed.first.dx, deformed.first.dy);
    for (var index = 0; index < deformed.length; index++) {
      final p0 = deformed[(index - 1 + deformed.length) % deformed.length];
      final p1 = deformed[index];
      final p2 = deformed[(index + 1) % deformed.length];
      final p3 = deformed[(index + 2) % deformed.length];
      final control1 = p1 + (p2 - p0) / 6;
      final control2 = p2 - (p3 - p1) / 6;
      path.cubicTo(
        control1.dx,
        control1.dy,
        control2.dx,
        control2.dy,
        p2.dx,
        p2.dy,
      );
    }
    return path..close();
  }

  static Offset _deformPoint(
    Offset point,
    Rect rect,
    Offset origin,
    Offset pull,
    double sigma,
    double localPressure,
  ) {
    final delta = point - origin;
    final influence = math.exp(-delta.distanceSquared / (2 * sigma * sigma));
    final centerDelta = point - rect.center;
    final normal = centerDelta.distanceSquared < 0.001
        ? Offset.zero
        : centerDelta / centerDelta.distance;
    final localPress = normal * (-1.85 * localPressure * influence);
    return point + pull * (0.18 + influence * 0.60) + localPress;
  }

  static Offset _limit(Offset value, double maximum) {
    if (value == Offset.zero || value.distance <= maximum) {
      return value;
    }
    return value / value.distance * maximum;
  }
}

abstract final class GlassGeometry {
  static GlassGeometryFrame resolve({
    required Size viewport,
    required double morph,
    required double separation,
    required Offset displacement,
    Offset cancelDisplacement = Offset.zero,
    Offset pointerPosition = Offset.zero,
    double press = 0,
    Offset pointerVelocity = Offset.zero,
    double settleWobble = 0,
    bool deformCancel = false,
    Offset? collapsedCenter,
    double? expandedGroupLeft,
    double? centerY,
    GlassTokens tokens = const GlassTokens(),
  }) {
    final safeMorph = morph.clamp(0.0, 1.06);
    final visibleMorph = _visualSpringValue(safeMorph);
    final safeSeparation = separation.clamp(0.0, 1.05);
    final visibleSeparation = _visualSpringValue(safeSeparation);
    final availableSearchWidth = math.max(
      176.0,
      viewport.width -
          tokens.horizontalMargin * 2 -
          tokens.cancelWidth -
          tokens.settledGap,
    );
    final searchWidth = math.min(tokens.maxSearchWidth, availableSearchWidth);
    final groupWidth = searchWidth + tokens.settledGap + tokens.cancelWidth;
    final finalMainLeft =
        expandedGroupLeft ?? (viewport.width - groupWidth) / 2;
    final finalMainCenterX = finalMainLeft + searchWidth / 2;
    final resolvedCollapsedCenter =
        collapsedCenter ?? Offset(viewport.width / 2, viewport.height * 0.40);
    final resolvedCenterY = centerY ?? resolvedCollapsedCenter.dy;

    final mainWidth = _lerp(
      tokens.collapsedDiameter,
      searchWidth,
      visibleMorph,
    );
    final mainHeight = _lerp(
      tokens.collapsedDiameter,
      tokens.expandedHeight,
      visibleMorph,
    );
    final mainCenter = Offset(
      _lerp(resolvedCollapsedCenter.dx, finalMainCenterX, visibleMorph),
      resolvedCenterY,
    );
    final mainRect = Rect.fromCenter(
      center: mainCenter,
      width: mainWidth,
      height: mainHeight,
    );

    final cancelVisible = visibleMorph > 0.22 || safeSeparation > 0.001;
    final emergeT = ((visibleSeparation - 0.06) / 0.94).clamp(0.0, 1.0);
    final cancelWidth = _lerp(16, tokens.cancelWidth, emergeT);
    final cancelHeight = _lerp(16, tokens.cancelHeight, emergeT);
    final finalCancelCenterX =
        finalMainLeft +
        searchWidth +
        tokens.settledGap +
        tokens.cancelWidth / 2;
    final budCenterX = mainRect.right - 12;
    final cancelCenter = Offset(
      _lerp(budCenterX, finalCancelCenterX, emergeT),
      resolvedCenterY,
    );
    final cancelRect = Rect.fromCenter(
      center: cancelCenter,
      width: cancelWidth,
      height: cancelHeight,
    );

    final bridgeT = ((1 - visibleSeparation) - 0.15) / 0.85;
    final neckRadius = cancelVisible
        ? math.pow(bridgeT.clamp(0.0, 1.0), 0.8).toDouble() * mainHeight * 0.44
        : 0.0;
    final neckLeft = math.min(mainRect.right - 4, cancelRect.left);
    final neckRight = math.max(mainRect.right - 4, cancelRect.left + 4);
    final neckRect = Rect.fromLTRB(
      neckLeft,
      resolvedCenterY - neckRadius,
      neckRight,
      resolvedCenterY + neckRadius,
    );

    Rect combined = mainRect;
    if (cancelVisible) {
      combined = combined.expandToInclude(cancelRect).expandToInclude(neckRect);
    }
    final settleDeformation = Offset(settleWobble, -settleWobble * 0.16);
    final pointerMainDeformation = deformCancel ? Offset.zero : displacement;
    final mainDeformation = pointerMainDeformation + settleDeformation;
    final cancelDeformation =
        (deformCancel ? cancelDisplacement : Offset.zero) +
        (cancelVisible ? settleDeformation * 0.38 : Offset.zero);
    final deformationExtent = math.max(
      mainDeformation.distance,
      cancelDeformation.distance,
    );
    final opticalBounds = combined.inflate(
      tokens.opticalMargin + deformationExtent + 8,
    );
    final iconCenter =
        Offset(
          _lerp(mainRect.center.dx, mainRect.left + 30, visibleMorph),
          mainRect.center.dy,
        ) +
        mainDeformation * 0.12;

    return GlassGeometryFrame(
      mainRect: mainRect,
      cancelRect: cancelRect,
      opticalBounds: opticalBounds,
      neckRect: neckRect,
      neckRadius: neckRadius,
      morph: visibleMorph,
      separation: visibleSeparation,
      cancelVisible: cancelVisible,
      cancelInteractive: visibleSeparation > 0.91 && visibleMorph > 0.88,
      iconCenter: iconCenter,
      deformationOrigin:
          pointerMainDeformation.distanceSquared > 0.001 ||
              deformCancel ||
              press > 0.001
          ? (pointerPosition == Offset.zero ? mainRect.center : pointerPosition)
          : settleDeformation.distanceSquared > 0.001
          ? Offset(mainRect.right, mainRect.center.dy)
          : mainRect.center,
      mainDeformation: mainDeformation,
      cancelDeformation: cancelDeformation,
      deformationVelocity: pointerVelocity,
      press: press,
      deformCancel: deformCancel,
    );
  }

  static double _smooth(double value) => value * value * (3 - 2 * value);

  static double _visualSpringValue(double value) {
    if (value < 0) {
      return value * 0.24;
    }
    if (value > 1) {
      return 1 + (value - 1) * 0.24;
    }
    return _smooth(value);
  }

  static double _lerp(double a, double b, double t) => a + (b - a) * t;
}
