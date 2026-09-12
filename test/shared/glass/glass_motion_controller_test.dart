import 'package:flutter_test/flutter_test.dart';
import 'package:folio/shared/glass/glass_motion_controller.dart';

void main() {
  test('the fixed-step springs settle open and closed', () {
    final motion = GlassMotionController();
    addTearDown(motion.dispose);

    motion.requestOpen();
    motion.stepForTest(1);
    expect(motion.morph, closeTo(1, 0.002));
    expect(motion.separation, closeTo(1, 0.002));
    expect(motion.state, GlassInteractionState.open);

    motion.requestClose();
    motion.stepForTest(1);
    motion.stepForTest(1);
    expect(motion.morph, closeTo(0, 0.002));
    expect(motion.separation, closeTo(0, 0.002));
    expect(motion.state, GlassInteractionState.idle);
  });

  test('drag displacement is bounded and returns after release', () {
    final motion = GlassMotionController();
    addTearDown(motion.dispose);
    const start = Offset(50, 50);

    motion.beginPointer(
      position: start,
      timestamp: Duration.zero,
      target: GlassPointerTarget.main,
    );
    motion.movePointer(
      position: const Offset(500, 300),
      timestamp: const Duration(milliseconds: 50),
    );
    motion.stepForTest(0.2);
    expect(motion.displacement.distance, lessThanOrEqualTo(30.001));

    motion.endPointer(
      position: const Offset(500, 300),
      timestamp: const Duration(milliseconds: 60),
    );
    motion.stepForTest(1);
    expect(motion.displacement.distance, lessThan(0.1));
  });
}
