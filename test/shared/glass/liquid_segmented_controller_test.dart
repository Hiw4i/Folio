import 'package:flutter_test/flutter_test.dart';
import 'package:folio/shared/glass/liquid_segmented_controller.dart';

void main() {
  test('lens stretches in transit and settles on the selected segment', () {
    final motion = LiquidSegmentedController(initialIndex: 0, itemCount: 5);
    addTearDown(motion.dispose);

    motion.select(4);
    motion.stepForTest(0.15);

    expect(motion.position, inExclusiveRange(0, 4));
    expect(motion.stretch, greaterThan(0.1));
    expect(motion.velocity, greaterThan(0));

    motion.stepForTest(1);
    motion.stepForTest(1);

    expect(motion.position, closeTo(4, 0.002));
    expect(motion.stretch, lessThan(0.01));
    expect(motion.velocity.abs(), lessThan(0.01));
  });

  test('reduced motion keeps deformation deliberately small', () {
    final motion = LiquidSegmentedController(initialIndex: 0, itemCount: 5);
    addTearDown(motion.dispose);
    motion.setReducedMotion(true);

    motion.select(4);
    motion.stepForTest(0.1);

    expect(motion.stretch, lessThanOrEqualTo(0.087));
  });
}
