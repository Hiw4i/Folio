import 'package:flutter/widgets.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:folio/shared/glass/liquid_glass.dart';
import 'package:lucide_flutter/lucide_flutter.dart';

void main() {
  setUp(() {
    AdaptiveGlassDebug.shaderFilterSupportedOverride = false;
  });

  tearDown(() {
    AdaptiveGlassDebug.shaderFilterSupportedOverride = null;
  });

  test('generated glyph masks contain coverage and transparency', () async {
    expect(await AdaptiveGlassDebug.textMaskHasCoverage(), isTrue);
    expect(
      await AdaptiveGlassDebug.iconMaskHasCoverage(LucideIcons.search),
      isTrue,
    );
    expect(
      await AdaptiveGlassDebug.iconMaskHasCoverage(LucideIcons.chevronLeft),
      isTrue,
    );
    expect(
      await AdaptiveGlassDebug.iconMaskHasCoverage(LucideIcons.moreVertical),
      isTrue,
    );
  });

  testWidgets('unsupported renderer uses visible outlined fallbacks', (
    tester,
  ) async {
    await tester.pumpWidget(
      const Directionality(
        textDirection: TextDirection.ltr,
        child: MediaQuery(
          data: MediaQueryData(devicePixelRatio: 2),
          child: ColoredBox(
            color: Color(0xFFFFFFFF),
            child: Row(
              mainAxisSize: MainAxisSize.min,
              children: <Widget>[
                AdaptiveGlassIcon(LucideIcons.search, size: 20),
                AdaptiveGlassText('Search', style: TextStyle(fontSize: 14)),
              ],
            ),
          ),
        ),
      ),
    );

    expect(find.byType(BackdropFilter), findsNothing);
    expect(find.byType(Icon), findsOneWidget);
    expect(find.text('Search'), findsOneWidget);
    expect(tester.takeException(), isNull);
  });

  testWidgets('adaptive text preserves its semantics label', (tester) async {
    final semantics = tester.ensureSemantics();

    await tester.pumpWidget(
      const Directionality(
        textDirection: TextDirection.ltr,
        child: MediaQuery(
          data: MediaQueryData(),
          child: AdaptiveGlassText(
            'short.pdf',
            semanticsLabel: 'A very long document name.pdf',
            style: TextStyle(fontSize: 14),
          ),
        ),
      ),
    );

    expect(find.bySemanticsLabel('A very long document name.pdf'), findsOne);
    semantics.dispose();
  });
}
