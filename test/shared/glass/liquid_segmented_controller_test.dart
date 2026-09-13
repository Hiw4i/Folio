import 'package:flutter_test/flutter_test.dart';
import 'package:folio/shared/glass/motion/liquid_segmented_controller.dart';

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

  test('a grabbed lens follows the pointer and snaps with momentum', () {
    final motion = LiquidSegmentedController(initialIndex: 0, itemCount: 5);
    addTearDown(motion.dispose);

    motion.beginPointer(
      position: const Offset(30, 29),
      timestamp: Duration.zero,
      itemExtent: 60,
      dragLens: true,
    );
    motion.movePointer(
      position: const Offset(210, 29),
      timestamp: const Duration(milliseconds: 100),
      itemExtent: 60,
    );
    motion.stepForTest(0.12);

    expect(motion.isDraggingLens, isTrue);
    expect(motion.position, greaterThan(0));
    expect(motion.stretch, greaterThan(0.1));
    expect(motion.press, greaterThan(0.8));

    final selected = motion.endPointer(
      position: const Offset(210, 29),
      timestamp: const Duration(milliseconds: 110),
      itemExtent: 60,
    );
    expect(selected, 3);
    expect(motion.isDraggingLens, isFalse);

    motion.stepForTest(1);
    motion.stepForTest(1);
    expect(motion.position, closeTo(3, 0.002));
  });
}
