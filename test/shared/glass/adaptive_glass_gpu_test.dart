// Requires a real Impeller renderer; software widget tests cannot verify
// backdrop filters. Enforce that requirement with FOLIO_REQUIRE_GPU=true.
import 'dart:convert';
import 'dart:ui' as ui;

import 'package:flutter/rendering.dart';
import 'package:flutter/services.dart';
import 'package:flutter/widgets.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:folio/shared/glass/widgets/adaptive_glass_foreground.dart';
import 'package:lucide_flutter/lucide_flutter.dart';

const _requireGpu = bool.fromEnvironment('FOLIO_REQUIRE_GPU');
const _sceneSize = Size(360, 240);
const _captureKey = ValueKey<String>('adaptive_gpu_scene');
const _textStyle = TextStyle(
  inherit: false,
  fontFamily: 'Inter',
  fontSize: 28,
  height: 1,
  fontWeight: FontWeight.w700,
);

Widget _control({
  required double left,
  required String id,
  double opacity = 1,
  double sigma = 0,
  Offset translation = Offset.zero,
}) => Positioned(
  left: left,
  top: 40,
  width: 150,
  height: 90,
  child: AdaptiveGlassForegroundGroup(
    key: ValueKey<String>('group_$id'),
    samplePoint: const Offset(75, 8),
    child: AdaptiveGlassEffects(
      opacity: opacity,
      blurSigma: sigma,
      child: Transform.translate(
        offset: translation,
        child: const Stack(
          children: <Widget>[
            Positioned(
              left: 10,
              top: 25,
              width: 32,
              height: 32,
              child: AdaptiveGlassIcon(LucideIcons.search, size: 32),
            ),
            Positioned(
              left: 52,
              top: 25,
              width: 90,
              height: 34,
              child: AdaptiveGlassText('MM', style: _textStyle),
            ),
          ],
        ),
      ),
    ),
  ),
);

Widget _scene({
  Color background = const Color(0xFFFFFFFF),
  double opacity = 1,
  double sigma = 0,
  Offset translation = Offset.zero,
  bool split = false,
}) => MediaQuery(
  data: const MediaQueryData(size: _sceneSize, devicePixelRatio: 1),
  child: Directionality(
    textDirection: TextDirection.ltr,
    child: RepaintBoundary(
      key: _captureKey,
      child: SizedBox.expand(
        child: ColoredBox(
          color: background,
          child: Stack(
            children: <Widget>[
              if (split)
                const Positioned(
                  left: 180,
                  top: 0,
                  width: 180,
                  height: 240,
                  child: ColoredBox(color: Color(0xFF080808)),
                ),
              _control(
                left: 10,
                id: 'left',
                opacity: opacity,
                sigma: sigma,
                translation: translation,
              ),
              if (split)
                _control(
                  left: 190,
                  id: 'right',
                  opacity: opacity,
                  sigma: sigma,
                  translation: translation,
                ),
            ],
          ),
        ),
      ),
    ),
  ),
);

Future<ByteData> _pixels(WidgetTester tester) async {
  final boundary = tester.renderObject<RenderRepaintBoundary>(
    find.byKey(_captureKey),
  );
  final image = await boundary.toImage(pixelRatio: 1);
  try {
    return (await image.toByteData(format: ui.ImageByteFormat.rawRgba))!;
  } finally {
    image.dispose();
  }
}

({int minimum, int maximum}) _redRange(ByteData data, Rect rect) {
  var minimum = 255;
  var maximum = 0;
  for (var y = rect.top.ceil(); y < rect.bottom.floor(); y++) {
    for (var x = rect.left.ceil(); x < rect.right.floor(); x++) {
      final red = data.getUint8((y * 360 + x) * 4);
      if (red < minimum) minimum = red;
      if (red > maximum) maximum = red;
    }
  }
  return (minimum: minimum, maximum: maximum);
}

void _setView(WidgetTester tester) {
  tester.view.devicePixelRatio = 1;
  tester.view.physicalSize = _sceneSize;
  addTearDown(tester.view.resetDevicePixelRatio);
  addTearDown(tester.view.resetPhysicalSize);
}

void main() {
  TestWidgetsFlutterBinding.ensureInitialized();
  final supported = ui.ImageFilter.isShaderFilterSupported;

  setUpAll(() async {
    if (!supported) return;
    // Use the project's real fonts, especially the Lucide search glyph, not
    // Flutter test's Ahem/tofu replacement. No font assets are copied by this patch.
    final manifest = jsonDecode(
      await rootBundle.loadString('FontManifest.json'),
    ) as List<dynamic>;
    for (final entry in manifest.cast<Map<String, dynamic>>()) {
      final loader = FontLoader(entry['family'] as String);
      for (final font
          in (entry['fonts'] as List<dynamic>).cast<Map<String, dynamic>>()) {
        loader.addFont(rootBundle.load(font['asset'] as String));
      }
      await loader.load();
    }
    await precacheAdaptiveGlassForeground();
  });

  test(
    'strict GPU invocation cannot silently pass on the fallback renderer',
    () {
      if (_requireGpu) {
        expect(
          supported,
          isTrue,
          reason:
              'Run with --enable-impeller on a supported GPU runner. '
              'Skipping shader pixels is not validation.',
        );
      }
    },
  );

  testWidgets(
    'actual search glyph and text stay black through fades and blur',
    (tester) async {
      _setView(tester);
      final before = AdaptiveGlassDebug.shaderCreations;
      for (final opacity in <double>[1, 0.88, 0.5, 0.25, 0.6, 1]) {
        await tester.pumpWidget(
          _scene(opacity: opacity, sigma: opacity == 1 ? 0 : 1.4),
        );
        await tester.pump();
        final pixels = await _pixels(tester);
        for (final rect in <Rect>[
          const Rect.fromLTWH(18, 62, 36, 38),
          const Rect.fromLTWH(60, 62, 94, 38),
        ]) {
          // A white-reset or missing glyph has no ink on the white scene.
          expect(_redRange(pixels, rect).minimum, lessThan(245));
        }
        expect(tester.takeException(), isNull);
      }
      expect(AdaptiveGlassDebug.shaderCreations - before, 2);
    },
    skip: !supported,
  );

  testWidgets('dark backgrounds keep white foreground during the same motion', (
    tester,
  ) async {
    _setView(tester);
    for (final opacity in <double>[1, 0.88, 0.25, 0.6, 1]) {
      await tester.pumpWidget(
        _scene(
          background: const Color(0xFF080808),
          opacity: opacity,
          sigma: opacity == 1 ? 0 : 1.4,
        ),
      );
      await tester.pump();
      final range = _redRange(
        await _pixels(tester),
        const Rect.fromLTWH(18, 62, 138, 38),
      );
      expect(range.maximum, greaterThan(20));
    }
  }, skip: !supported);

  testWidgets(
    'neighboring controls adapt independently, icon and label agree',
    (tester) async {
      _setView(tester);
      await tester.pumpWidget(_scene(split: true, opacity: 0.88));
      await tester.pump();
      final pixels = await _pixels(tester);
      for (final rect in <Rect>[
        const Rect.fromLTWH(18, 62, 36, 38),
        const Rect.fromLTWH(60, 62, 94, 38),
      ]) {
        expect(_redRange(pixels, rect).minimum, lessThan(100));
        expect(
          _redRange(pixels, rect.shift(const Offset(180, 0))).maximum,
          greaterThan(160),
        );
      }
    },
    skip: !supported,
  );

  testWidgets(
    'moving foreground reuses shaders and masks without a white frame',
    (tester) async {
      _setView(tester);
      await tester.pumpWidget(_scene());
      await tester.pump();
      final shaders = AdaptiveGlassDebug.shaderCreations;
      final masks = AdaptiveGlassDebug.maskCreations;
      for (var i = 0; i < 16; i++) {
        await tester.pumpWidget(
          _scene(
            opacity: 0.88,
            sigma: 1.2,
            translation: Offset(i * 0.2, i * 0.15),
          ),
        );
        await tester.pump();
        expect(
          _redRange(
            await _pixels(tester),
            const Rect.fromLTWH(18, 62, 144, 44),
          ).minimum,
          lessThan(230),
        );
      }
      expect(AdaptiveGlassDebug.shaderCreations, shaders);
      expect(AdaptiveGlassDebug.maskCreations, masks);
    },
    skip: !supported,
  );

  testWidgets(
    'foreground does not color the extra sample area or glass surface',
    (tester) async {
      _setView(tester);
      await tester.pumpWidget(_scene(opacity: 0.88, sigma: 1.4));
      await tester.pump();
      final pixels = await _pixels(tester);
      final clear = _redRange(pixels, const Rect.fromLTWH(65, 44, 30, 9));
      // Allow one 8-bit quantization step at coverage-mark boundaries.
      expect(clear.minimum, greaterThanOrEqualTo(254));
      await tester.pumpWidget(_scene(opacity: 0));
      await tester.pump();
      final hidden = _redRange(
        await _pixels(tester),
        const Rect.fromLTWH(15, 45, 145, 65),
      );
      expect(hidden.minimum, 255);
    },
    skip: !supported,
  );
}
