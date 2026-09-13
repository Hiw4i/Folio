import 'package:flutter_test/flutter_test.dart';
import 'package:flutter/widgets.dart';
import 'package:folio/shared/glass/core/glass_geometry.dart';

import 'package:folio/shared/glass/motion/glass_motion_controller.dart';
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

  test('press expands the search material instead of shrinking it', () {
    final motion = GlassMotionController();
    addTearDown(motion.dispose);
    final resting = GlassGeometry.resolve(
      viewport: const Size(400, 200),
      morph: motion.morph,
      separation: motion.separation,
      displacement: motion.displacement,
    );

    motion.beginPointer(
      position: resting.mainRect.center,
      timestamp: Duration.zero,
      target: GlassPointerTarget.main,
    );
    motion.stepForTest(0.12);
    final pressed = GlassGeometry.resolve(
      viewport: const Size(400, 200),
      morph: motion.morph,
      separation: motion.separation,
      displacement: motion.displacement,
      pointerPosition: resting.mainRect.center,
      press: motion.press,
    );

    expect(pressed.mainRect.width, greaterThan(resting.mainRect.width));
    expect(pressed.mainRect.height, greaterThan(resting.mainRect.height));
  });

  test('search foreground displacement is capped independently', () {
    final resting = GlassGeometry.resolve(
      viewport: const Size(400, 200),
      morph: 0,
      separation: 0,
      displacement: Offset.zero,
    );
    final dragged = GlassGeometry.resolve(
      viewport: const Size(400, 200),
      morph: 0,
      separation: 0,
      displacement: const Offset(30, 0),
      pointerVelocity: const Offset(12000, 0),
      press: 1,
    );

    expect(
      (dragged.iconCenter - resting.iconCenter).distance,
      lessThanOrEqualTo(8.001),
    );
  });

  test('search icon trails the expanding liquid material', () {
    final frame = GlassGeometry.resolve(
      viewport: const Size(400, 200),
      morph: 0.5,
      separation: 0.5,
      displacement: Offset.zero,
    );

    expect(frame.iconCenter.dx, greaterThan(frame.mainRect.left + 30));
    expect(frame.iconCenter.dx, lessThan(frame.mainRect.center.dx));
  });
}
