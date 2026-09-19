import 'dart:ui' as ui;

import 'package:flutter/widgets.dart';

import '../../settings/folio_settings_scope.dart';

import '../core/glass_tokens.dart';
import 'liquid_surface_style.dart';

/// Canonical liquid surfaces: one blur, one shadow language, one rim.
///
/// Interactive (deformed) surfaces keep using `GlassShell` directly — it
/// already shares [LiquidBlur.filter]. Static surfaces (panels, segmented
/// tracks) use [LiquidCase] so they stop drifting apart with their own
/// blur sigmas (11 vs 13.5 vs 16) and border colors.
abstract final class LiquidBlur {
  /// Single shared backdrop filter for every liquid surface.
  ///
  /// Previously `GlassShell` used 13.5, the segmented track 11 and
  /// `GlassPanel` 16 — now all resolve to [GlassTokens.blurSigma].
  static final ui.ImageFilter filter = ui.ImageFilter.blur(
    sigmaX: const GlassTokens().blurSigma,
    sigmaY: const GlassTokens().blurSigma,
    tileMode: ui.TileMode.mirror,
  );

  /// Blur filters are quantized so animated consumers can change sigma
  /// without allocating a new native filter for every animation frame.
  static final Map<double, ui.ImageFilter> _animatedFilters =
      <double, ui.ImageFilter>{};

  static ui.ImageFilter filterFor(double sigma) {
    final rest = const GlassTokens().blurSigma;
    sigma = sigma.isFinite ? sigma.clamp(0.0, rest) : rest;
    if (sigma >= rest - 0.001) {
      return filter;
    }
    final quantized = (sigma * 2).round() / 2;
    var animated = _animatedFilters[quantized];
    if (animated == null) {
      if (_animatedFilters.length >= 32) {
        _animatedFilters.clear();
      }
      animated = ui.ImageFilter.blur(
        sigmaX: quantized,
        sigmaY: quantized,
        tileMode: ui.TileMode.mirror,
      );
      _animatedFilters[quantized] = animated;
    }
    return animated;
  }
}

/// Provides transition blur and foreground opacity for liquid surfaces in a
/// subtree.
///
/// The scope is optional: normal glass remains at [GlassTokens.blurSigma].
/// Opacity is consumed below each [BackdropFilter], never around it.
class LiquidBlurScope extends InheritedWidget {
  const LiquidBlurScope({
    this.sigma,
    required this.opacity,
    required super.child,
    super.key,
  });

  final double? sigma;
  final double opacity;

  static double? maybeOf(BuildContext context) =>
      context.dependOnInheritedWidgetOfExactType<LiquidBlurScope>()?.sigma;

  static double? maybeOpacityOf(BuildContext context) =>
      context.dependOnInheritedWidgetOfExactType<LiquidBlurScope>()?.opacity;

  @override
  bool updateShouldNotify(LiquidBlurScope oldWidget) =>
      sigma != oldWidget.sigma || opacity != oldWidget.opacity;
}

/// Fades glass paint and foreground separately, below backdrop filters.
/// An outer Opacity would isolate the backdrop and make its luminance black.
/// Nested fades multiply without resetting the child's physics/editable state.
class LiquidFade extends StatelessWidget {
  const LiquidFade({required this.opacity, required this.child, super.key});

  final double opacity;
  final Widget child;

  @override
  Widget build(BuildContext context) {
    final combined = ((LiquidBlurScope.maybeOpacityOf(context) ?? 1) * opacity)
        .clamp(0.0, 1.0);
    return LiquidBlurScope(
      sigma: LiquidBlurScope.maybeOf(context),
      opacity: combined,
      // Keep state, but do not leave a fully blurred invisible button behind
      // when the search navigator reaches its hidden endpoint.
      child: Offstage(offstage: combined <= 0, child: child),
    );
  }
}

/// Static (non-deforming) liquid shell: the `GlassPanel` look as a mode of
/// the same library instead of a separate implementation.
///
/// [fill] varies by use case (translucent track vs opaque panel with text)
/// but blur, shadow, rim and gradient overlay are shared.
class LiquidCase extends StatelessWidget {
  const LiquidCase({
    required this.child,
    this.borderRadius = 24,
    this.padding = EdgeInsets.zero,
    this.fill = const Color(0xB31A1B1E),
    super.key,
  });

  /// Translucent track behind a moving lens (segmented control).
  const LiquidCase.track({super.key})
    : child = const SizedBox.expand(),
      borderRadius = 27,
      padding = EdgeInsets.zero,
      fill = const Color(0x161A1B1D);

  final Widget child;
  final double borderRadius;
  final EdgeInsetsGeometry padding;
  final Color fill;

  @override
  Widget build(BuildContext context) {
    final blurEnabled = FolioSettingsScope.blurEnabledOf(context);
    final radius = BorderRadius.circular(borderRadius);
    final transitionBlur = LiquidBlurScope.maybeOf(context);
    final transitionOpacity = LiquidBlurScope.maybeOpacityOf(context) ?? 1.0;
    return RepaintBoundary(
      child: DecoratedBox(
        decoration: BoxDecoration(
          borderRadius: radius,
          // Same shadow language as GlassShell (offset y=7-8, soft black).
          boxShadow: !blurEnabled
              ? const <BoxShadow>[]
              : transitionOpacity >= 0.999
              ? const <BoxShadow>[
                  BoxShadow(
                    color: Color(0x4D020809),
                    blurRadius: 22,
                    offset: Offset(0, 8),
                  ),
                ]
              : <BoxShadow>[
                  BoxShadow(
                    color: const Color(0xFF020809)
                        .withValues(alpha: (0x4D / 255) * transitionOpacity),
                    blurRadius: 22,
                    offset: const Offset(0, 8),
                  ),
                ],
        ),
        child: ClipRRect(
          borderRadius: radius,
          child: BackdropFilter.grouped(
            enabled: blurEnabled,
            filter: !blurEnabled || transitionBlur == null
                ? LiquidBlur.filter
                : LiquidBlur.filterFor(transitionBlur),
            child: Opacity(
              opacity: transitionOpacity,
              child: DecoratedBox(
                decoration: BoxDecoration(
                  color: blurEnabled ? fill : LiquidSurfaceStyle.opaqueFill,
                  borderRadius: radius,
                  gradient: blurEnabled
                      ? const LinearGradient(
                          begin: Alignment.topLeft,
                          end: Alignment.bottomRight,
                          colors: <Color>[Color(0x1FFFFFFF), Color(0x08FFFFFF)],
                        )
                      : null,
                ),
                child: CustomPaint(
                  foregroundPainter: LiquidCaseRimPainter(radius: radius),
                  child: Padding(padding: padding, child: child),
                ),
              ),
            ),
          ),
        ),
      ),
    );
  }
}
