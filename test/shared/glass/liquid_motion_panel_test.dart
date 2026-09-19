import 'package:flutter/gestures.dart';
import 'package:flutter/material.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:folio/shared/glass/surface/glass_shell.dart';
import 'package:folio/shared/glass/surface/liquid_surface.dart';
import 'package:folio/shared/glass/widgets/liquid_container.dart';
import 'package:folio/shared/glass/widgets/liquid_motion_panel.dart';
import 'package:folio/shared/settings/folio_settings.dart';
import 'package:folio/shared/settings/folio_settings_controller.dart';
import 'package:folio/shared/settings/folio_settings_scope.dart';

import '../../support/memory_settings_store.dart';

final _panel = find.byType(LiquidMotionPanel);
final _shell = find.byType(GlassShell);
const _bodyKey = ValueKey<String>('panel_body');

void main() {
  testWidgets('content sizes the material without optical layout padding', (
    tester,
  ) async {
    await _pumpPanel(tester);
    expect(tester.getSize(_panel), const Size(320, 220));
    expect(tester.getSize(_shell), const Size(400, 300));
    final shell = tester.widget<GlassShell>(_shell);
    expect(shell.path.getBounds(), const Rect.fromLTWH(40, 40, 320, 220));
    expect(shell.path.contains(const Offset(41, 41)), isFalse);
    expect(shell.path.contains(const Offset(72, 41)), isTrue);
    expect(find.byType(LiquidCase), findsNothing);
    expect(find.byType(BackdropFilter), findsOneWidget);
    expect(tester.binding.transientCallbackCount, 0);
    expect(tester.takeException(), isNull);
  });

  testWidgets('only the outer shell deforms and returns after a drag', (
    tester,
  ) async {
    var builds = 0;
    await _pumpPanel(
      tester,
      child: Builder(
        builder: (_) {
          builds++;
          return const SizedBox(key: _bodyKey, height: 220, width: 320);
        },
      ),
    );
    final body = tester.getRect(find.byKey(_bodyKey));
    final count = builds;
    final resting = tester.widget<GlassShell>(_shell).path.getBounds();
    final gesture = await tester.startGesture(body.center);
    await tester.pump();
    await tester.pump(const Duration(milliseconds: 80));
    await gesture.moveBy(const Offset(70, 30));
    await tester.pump(const Duration(milliseconds: 80));
    expect(tester.widget<GlassShell>(_shell).press, greaterThan(0));
    expect(tester.widget<GlassShell>(_shell).path.getBounds(), isNot(resting));
    expect(tester.getRect(find.byKey(_bodyKey)), body);
    expect(builds, count);
    await gesture.up();
    await tester.pumpAndSettle();
    expect(tester.widget<GlassShell>(_shell).press, lessThan(0.01));
    final settled = tester.widget<GlassShell>(_shell).path.getBounds();
    expect(settled.left, closeTo(resting.left, 0.15));
    expect(settled.top, closeTo(resting.top, 0.15));
    expect(tester.binding.transientCallbackCount, 0);
    expect(tester.takeException(), isNull);
  });

  testWidgets('inner buttons and scrolling keep their gestures and state', (
    tester,
  ) async {
    var taps = 0;
    final scroll = ScrollController();
    addTearDown(scroll.dispose);
    await _pumpPanel(
      tester,
      child: SizedBox(
        height: 220,
        child: ListView(
          controller: scroll,
          children: <Widget>[
            TextButton(
              onPressed: () => taps++,
              child: const Text('Inner action'),
            ),
            const SizedBox(height: 1000),
          ],
        ),
      ),
    );
    await tester.tap(find.text('Inner action'));
    await tester.pumpAndSettle();
    expect(taps, 1);
    final body = tester.getRect(_panel);
    await tester.dragFrom(body.center, const Offset(0, -90));
    await tester.pumpAndSettle();
    expect(scroll.offset, greaterThan(0));
    expect(taps, 1);
    expect(tester.takeException(), isNull);
  });

  testWidgets('motion and blur toggle independently without remounting', (
    tester,
  ) async {
    final settings = await _pumpPanel(tester);
    final element = tester.element(find.byKey(_bodyKey));
    final geometry = tester.getRect(_panel);
    final gesture = await tester.startGesture(geometry.center);
    await tester.pump();
    await tester.pump(const Duration(milliseconds: 80));
    expect(tester.widget<GlassShell>(_shell).press, greaterThan(0));
    settings.setLiquidMotionEnabled(false);
    await tester.pumpAndSettle();
    expect(tester.widget<GlassShell>(_shell).press, 0);
    expect(
      tester.widget<BackdropFilter>(find.byType(BackdropFilter)).enabled,
      isTrue,
    );
    expect(tester.binding.transientCallbackCount, 0);
    await gesture.up();
    for (final enabled in <bool>[false, true]) {
      settings.setBlurEnabled(enabled);
      await tester.pumpAndSettle();
      expect(
        tester.widget<BackdropFilter>(find.byType(BackdropFilter)).enabled,
        enabled,
      );
      expect(tester.element(find.byKey(_bodyKey)), same(element));
      expect(tester.getRect(_panel), geometry);
    }
    settings.setLiquidMotionEnabled(true);
    await tester.pumpAndSettle();
    final next = await tester.startGesture(geometry.center);
    await tester.pump();
    await tester.pump(const Duration(milliseconds: 80));
    expect(tester.widget<GlassShell>(_shell).press, greaterThan(0));
    await next.cancel();
    await tester.pumpAndSettle();
    expect(tester.binding.transientCallbackCount, 0);
    expect(tester.element(find.byKey(_bodyKey)), same(element));
    expect(tester.takeException(), isNull);
  });

  for (final reducedMotion in <bool>[false, true]) {
    testWidgets('disabled deformation stays still (reduced=$reducedMotion)', (
      tester,
    ) async {
      await _pumpPanel(
        tester,
        reducedMotion: reducedMotion,
        motion: reducedMotion,
      );
      final rect = tester.widget<GlassShell>(_shell).path.getBounds();
      final gesture = await tester.startGesture(tester.getCenter(_panel));
      await gesture.moveBy(const Offset(80, 30));
      await tester.pump(const Duration(milliseconds: 120));
      expect(tester.widget<GlassShell>(_shell).press, 0);
      expect(tester.widget<GlassShell>(_shell).path.getBounds(), rect);
      expect(tester.binding.transientCallbackCount, 0);
      await gesture.up();
      await tester.pumpAndSettle();
      expect(tester.takeException(), isNull);
    });
  }

  testWidgets('a second pointer cannot release the first; cancel settles', (
    tester,
  ) async {
    await _pumpPanel(tester);
    final center = tester.getCenter(_panel);
    final first = await tester.startGesture(center, pointer: 1);
    await tester.pump();
    await tester.pump(const Duration(milliseconds: 80));
    final second = await tester.startGesture(
      center + const Offset(20, 0),
      pointer: 2,
    );
    await second.up();
    await tester.pump(const Duration(milliseconds: 80));
    expect(tester.widget<GlassShell>(_shell).press, greaterThan(0.5));
    await first.cancel();
    await tester.pumpAndSettle();
    expect(tester.widget<GlassShell>(_shell).press, lessThan(0.01));
    expect(tester.binding.transientCallbackCount, 0);
    expect(tester.takeException(), isNull);
  });

  testWidgets('secondary mouse click does not press the material', (
    tester,
  ) async {
    await _pumpPanel(tester);
    final gesture = await tester.startGesture(
      tester.getCenter(_panel),
      kind: PointerDeviceKind.mouse,
      buttons: kSecondaryMouseButton,
    );
    await tester.pump(const Duration(milliseconds: 120));
    expect(tester.widget<GlassShell>(_shell).press, 0);
    expect(tester.binding.transientCallbackCount, 0);
    await gesture.up();
    await tester.pumpAndSettle();
  });

  testWidgets('disposing during a press leaves no ticker', (tester) async {
    await _pumpPanel(tester);
    final gesture = await tester.startGesture(tester.getCenter(_panel));
    await tester.pump();
    await tester.pump(const Duration(milliseconds: 50));
    await tester.pumpWidget(const SizedBox.shrink());
    await gesture.cancel();
    await tester.pumpAndSettle();
    expect(tester.binding.transientCallbackCount, 0);
    expect(tester.takeException(), isNull);
  });
}

Future<FolioSettingsController> _pumpPanel(
  WidgetTester tester, {
  Widget child = const SizedBox(key: _bodyKey, height: 220, width: 320),
  bool motion = true,
  bool reducedMotion = false,
}) async {
  final settings = FolioSettingsController(
    store: MemorySettingsStore(
      FolioSettings(blurEnabled: true, liquidMotionEnabled: motion),
    ),
  );
  await settings.load();
  addTearDown(() async {
    await tester.pumpWidget(const SizedBox.shrink());
    settings.dispose();
  });
  await tester.pumpWidget(
    FolioSettingsScope(
      controller: settings,
      child: MaterialApp(
        home: MediaQuery(
          data: MediaQueryData(disableAnimations: reducedMotion),
          child: Scaffold(
            body: Center(
              child: SizedBox(
                width: 320,
                child: LiquidGlass.panel(
                  liquidMotion: true,
                  borderRadius: 32,
                  child: child,
                ),
              ),
            ),
          ),
        ),
      ),
    ),
  );
  await tester.pumpAndSettle();
  return settings;
}
