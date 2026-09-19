import 'package:flutter/widgets.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:folio/shared/glass/core/glass_geometry.dart';
import 'package:folio/shared/glass/core/glass_tokens.dart';

GlassGeometryFrame _expanded(Size viewport) {
  return GlassGeometry.resolve(
    viewport: viewport,
    morph: 1,
    separation: 1,
    displacement: Offset.zero,
    collapsedCenter: Offset(
      viewport.width - GlassTokens().horizontalMargin - 27,
      viewport.height - 45,
    ),
    anchorExpandedRight: true,
    centerY: viewport.height - 45,
  );
}

void main() {
  test('expanded search group hugs the right edge on wide screens', () {
    // 2000px landscape: search caps at 420 + 12 gap + 92 cancel = 524.
    final frame = _expanded(const Size(2000, 900));
    expect(frame.mainRect.left, 2000 - 16 - 524);
    expect(frame.mainRect.right, 2000 - 16 - 524 + 420);
    expect(frame.cancelRect.right, lessThanOrEqualTo(2000 - 16 + 0.5));
    // The whole group sits in the right half, next to the collapsed button.
    expect(frame.mainRect.left, greaterThan(2000 / 2));
  });

  test('narrow screens keep the full-width group at the margin', () {
    // 400px portrait: 264 + 12 + 92 = 368, left stays 16 as before.
    final frame = _expanded(const Size(400, 800));
    expect(frame.mainRect.left, 16);
    expect(frame.mainRect.right, 16 + 264);
    expect(frame.cancelRect.right, lessThanOrEqualTo(400 - 16 + 0.5));
  });
}
