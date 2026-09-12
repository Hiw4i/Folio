import 'package:flutter_test/flutter_test.dart';
import 'package:flutter/widgets.dart';
import 'package:folio/shared/glass/glass_button_controller.dart';
import 'package:folio/shared/glass/glass_geometry.dart';
import 'package:folio/shared/glass/liquid_shape.dart';

void main() {
  test('pressed liquid material grows and springs back after release', () {
    final motion = GlassButtonController();
    addTearDown(motion.dispose);
    const base = Rect.fromLTWH(20, 20, 120, 56);

    motion.beginPointer(position: base.center, timestamp: Duration.zero);
    motion.stepForTest(0.12);
    final pressed = LiquidShape.expandedRect(base, press: motion.press);

    expect(motion.press, greaterThan(0.8));
    expect(pressed.width, greaterThan(base.width));
    expect(pressed.height, greaterThan(base.height));
    expect(pressed.center, base.center);
    final pressedPath = GlassGeometryFrame.deformedCapsule(
      rect: pressed,
      origin: base.center,
      press: motion.press,
    );
    expect(pressedPath.getBounds().width, greaterThan(base.width));
    expect(pressedPath.getBounds().height, greaterThan(base.height));

    motion.endPointer();
    motion.stepForTest(1);
    final settled = LiquidShape.expandedRect(base, press: motion.press);
    expect(settled.width, closeTo(base.width, 0.01));
    expect(settled.height, closeTo(base.height, 0.01));
  });

  test(
    'moving material grows in both axes while stretching in travel axis',
    () {
      const base = Rect.fromLTWH(0, 0, 80, 48);

      final moving = LiquidShape.expandedRect(base, travel: 1);

      expect(moving.width, greaterThan(base.width * 1.4));
      expect(moving.height, greaterThan(base.height * 1.08));
      expect(moving.center, base.center);
    },
  );
}
