import 'dart:math' as math;

import 'package:flutter/widgets.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:folio/features/reader/widgets/reader_chrome.dart';
import 'package:folio/shared/glass/surface/liquid_surface.dart';
import 'package:folio/shared/glass/widgets/adaptive_glass_foreground.dart';
import 'package:folio/shared/glass/widgets/liquid_morphing_control.dart';
import 'package:folio/shared/glass/widgets/liquid_search_control.dart';
import 'package:folio/shared/settings/folio_settings.dart';
import 'package:folio/shared/settings/folio_settings_controller.dart';
import 'package:folio/shared/settings/folio_settings_scope.dart';
import 'package:lucide_flutter/lucide_flutter.dart';

import '../../support/memory_settings_store.dart';

Widget _host(Widget child) => MediaQuery(
  data: const MediaQueryData(),
  child: Directionality(textDirection: TextDirection.ltr, child: child),
);

void _assertNoIsolatingAncestors(WidgetTester tester, Finder glyphs) {
  expect(glyphs, findsWidgets);
  for (final element in glyphs.evaluate()) {
    var foundGroup = false;
    element.visitAncestorElements((ancestor) {
      if (ancestor.widget is AdaptiveGlassForegroundGroup) {
        foundGroup = true;
        return false;
      }
      // Fallbacks may have these as descendants, never above the glyph.
      expect(ancestor.widget, isNot(isA<Opacity>()));
      expect(ancestor.widget, isNot(isA<ImageFiltered>()));
      return true;
    });
    expect(foundGroup, isTrue);
  }
}

void main() {
  setUp(() => AdaptiveGlassDebug.shaderFilterSupportedOverride = false);
  tearDown(() => AdaptiveGlassDebug.shaderFilterSupportedOverride = null);

  testWidgets(
    'foreground scopes multiply alpha and compose Gaussian variance',
    (tester) async {
      late AdaptiveGlassEffectData seen;
      await tester.pumpWidget(
        _host(
          AdaptiveGlassEffects(
            opacity: 0.8,
            blurSigma: 1.2,
            child: AdaptiveGlassEffects(
              opacity: 0.5,
              blurSigma: 0.9,
              child: Builder(
                builder: (context) {
                  seen = AdaptiveGlassEffects.of(context);
                  return const SizedBox.shrink();
                },
              ),
            ),
          ),
        ),
      );
      expect(seen.opacity, closeTo(0.4, 1e-10));
      expect(seen.blurSigma, closeTo(1.5, 1e-10));
      expect(find.byType(Opacity), findsNothing);
      expect(find.byType(ImageFiltered), findsNothing);
    },
  );

  testWidgets('decorations consume effects without remounting at endpoints', (
    tester,
  ) async {
    final key = GlobalKey<_MountProbeState>();
    var mounts = 0;
    Widget build(double opacity, double sigma) => _host(
      AdaptiveGlassEffects(
        opacity: opacity,
        blurSigma: sigma,
        child: AdaptiveGlassDecoration(
          child: _MountProbe(key: key, onMount: () => mounts++),
        ),
      ),
    );
    await tester.pumpWidget(build(1, 0));
    final state = key.currentState;
    for (final opacity in <double>[0.88, 0.2, 0, 0.5, 1]) {
      await tester.pumpWidget(build(opacity, opacity == 1 ? 0 : 1.6));
      expect(key.currentState, same(state));
      expect(tester.widget<Opacity>(find.byType(Opacity)).opacity, opacity);
    }
    expect(mounts, 1);
    expect(tester.takeException(), isNull);
  });

  testWidgets('unsupported icon and text still honor their foreground alpha', (
    tester,
  ) async {
    await tester.pumpWidget(
      _host(
        const AdaptiveGlassEffects(
          opacity: 0.38,
          child: Row(
            children: <Widget>[
              AdaptiveGlassIcon(LucideIcons.search),
              AdaptiveGlassText('Search', style: TextStyle(fontSize: 16)),
            ],
          ),
        ),
      ),
    );
    final fades = tester.widgetList<Opacity>(find.byType(Opacity)).toList();
    expect(fades, hasLength(2));
    expect(fades.every((fade) => fade.opacity == 0.38), isTrue);
    expect(find.byType(Icon), findsOneWidget);
    expect(find.text('Search'), findsOneWidget);
  });

  testWidgets('search icon has no opacity buffer at rest or mid morph', (
    tester,
  ) async {
    await tester.pumpWidget(
      _host(
        Overlay(
          initialEntries: <OverlayEntry>[
            OverlayEntry(
              builder: (_) => Align(
                alignment: Alignment.bottomCenter,
                child: SizedBox(
                  width: 412,
                  height: 200,
                  child: LiquidSearchControl(onChanged: (_) {}),
                ),
              ),
            ),
          ],
        ),
      ),
    );
    final icon = find.byWidgetPredicate(
      (widget) =>
          widget is AdaptiveGlassIcon && widget.icon == LucideIcons.search,
    );
    _assertNoIsolatingAncestors(tester, icon);
    tester
        .state<LiquidSearchControlState>(find.byType(LiquidSearchControl))
        .open();
    await tester.pump();
    await tester.pump(const Duration(milliseconds: 80));
    _assertNoIsolatingAncestors(tester, icon);
    await tester.pumpAndSettle();
    _assertNoIsolatingAncestors(tester, find.byType(AdaptiveGlassText));
    // Search and Cancel must not collapse into one background sample group.
    expect(find.byType(AdaptiveGlassForegroundGroup), findsNWidgets(2));
    await tester.pumpWidget(const SizedBox.shrink());
  });

  testWidgets('menu text keeps the backdrop path while opening and closing', (
    tester,
  ) async {
    final controller = FolioSettingsController(
      store: MemorySettingsStore(const FolioSettings(blurEnabled: true)),
    );
    await controller.load();
    addTearDown(controller.dispose);
    await tester.pumpWidget(
      FolioSettingsScope(
        controller: controller,
        child: _host(
          LiquidMorphingControl(
            geometryBuilder: (_) => const LiquidMorphGeometry(
              collapsedRect: Rect.fromLTWH(300, 20, 48, 48),
              expandedRect: Rect.fromLTWH(140, 20, 208, 116),
            ),
            collapsedSemanticsLabel: 'Open menu',
            collapsedChild: const Center(
              child: AdaptiveGlassIcon(LucideIcons.moreVertical),
            ),
            expandedChild: const Center(
              child: AdaptiveGlassText('Copy', style: TextStyle(fontSize: 16)),
            ),
          ),
        ),
      ),
    );
    final state = tester.state<LiquidMorphingControlState>(
      find.byType(LiquidMorphingControl),
    );
    state.open();
    await tester.pump();
    await tester.pump(const Duration(milliseconds: 80));
    _assertNoIsolatingAncestors(tester, find.byType(AdaptiveGlassText));
    final text = find.byWidgetPredicate(
      (w) => w is AdaptiveGlassText && w.data == 'Copy',
    );
    expect(
      AdaptiveGlassEffects.of(tester.element(text)).blurSigma,
      greaterThan(0),
    );
    await tester.pumpAndSettle();
    state.close();
    await tester.pump();
    await tester.pump(const Duration(milliseconds: 80));
    _assertNoIsolatingAncestors(tester, find.byType(AdaptiveGlassText));
    await tester.pumpAndSettle();
  });

  testWidgets('nested chrome fades keep sigma and multiply opacity', (
    tester,
  ) async {
    double? opacity;
    double? sigma;
    await tester.pumpWidget(
      _host(
        LiquidBlurScope(
          sigma: 9,
          opacity: 0.8,
          child: LiquidFade(
            opacity: 0.5,
            child: LiquidFade(
              opacity: 0.25,
              child: Builder(
                builder: (context) {
                  sigma = LiquidBlurScope.maybeOf(context);
                  opacity = LiquidBlurScope.maybeOpacityOf(context);
                  return const SizedBox.shrink();
                },
              ),
            ),
          ),
        ),
      ),
    );
    expect(sigma, 9);
    expect(opacity, closeTo(0.1, 1e-10));
    expect(find.byType(Opacity), findsNothing);
  });

  testWidgets('chrome preserves its mounted child across the shown endpoint', (
    tester,
  ) async {
    final progress = AnimationController(vsync: tester, value: 1);
    addTearDown(progress.dispose);
    var mounts = 0;
    await tester.pumpWidget(
      _host(
        ReaderChromeShell(
          progress: progress,
          hiddenDy: -60,
          child: _MountProbe(onMount: () => mounts++),
        ),
      ),
    );
    for (final value in <double>[0.98, 0.5, 1, 0.2, 1]) {
      progress.value = value;
      await tester.pump();
      expect(mounts, 1);
      expect(find.byType(Opacity), findsNothing);
    }
    progress.value = 0;
    await tester.pump();
    expect(find.byType(_MountProbe), findsNothing);
  });

  testWidgets('zero glass fade stops paint without discarding control state', (
    tester,
  ) async {
    var mounts = 0;
    final key = GlobalKey<_MountProbeState>();
    Widget build(double opacity) => _host(
      LiquidFade(
        opacity: opacity,
        child: _MountProbe(key: key, onMount: () => mounts++),
      ),
    );
    await tester.pumpWidget(build(1));
    final state = key.currentState;
    await tester.pumpWidget(build(0));
    expect(tester.widget<Offstage>(find.byType(Offstage)).offstage, isTrue);
    expect(key.currentState, same(state));
    await tester.pumpWidget(build(1));
    expect(key.currentState, same(state));
    expect(mounts, 1);
  });

  test('effect values compare by value', () {
    expect(const AdaptiveGlassEffectData(), const AdaptiveGlassEffectData());
    expect(
      const AdaptiveGlassEffectData(opacity: 0.5),
      isNot(const AdaptiveGlassEffectData()),
    );
    expect(
      const AdaptiveGlassEffectData(blurSigma: 1).hashCode,
      const AdaptiveGlassEffectData(blurSigma: 1).hashCode,
    );
    expect(math.sqrt(1.2 * 1.2 + 0.9 * 0.9), closeTo(1.5, 1e-10));
  });
}

class _MountProbe extends StatefulWidget {
  const _MountProbe({required this.onMount, super.key});
  final VoidCallback onMount;
  @override
  State<_MountProbe> createState() => _MountProbeState();
}

class _MountProbeState extends State<_MountProbe> {
  @override
  void initState() {
    super.initState();
    widget.onMount();
  }

  @override
  Widget build(BuildContext context) => const SizedBox(width: 20, height: 20);
}
