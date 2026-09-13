import 'package:flutter_test/flutter_test.dart';
import 'package:folio/shared/glass/core/glass_tokens.dart';
import 'package:folio/shared/glass/core/liquid_motion_controller.dart';
import 'package:folio/shared/glass/motion/glass_motion_controller.dart';
import 'package:folio/shared/glass/motion/liquid_segmented_controller.dart';

final double _rest = const GlassTokens().blurSigma;
final double _floor = const GlassTokens().minMotionBlurSigma;
final double _minScale = _floor / _rest;

void main() {
  test('backdrop blur is full and exact at rest', () {
    final motion = GlassMotionController(morphEnabled: false);
    addTearDown(motion.dispose);
    expect(motion.backdropScale, 1.0);
    expect(motion.backdropBlurSigma, _rest);
  });

  test('tap without drag keeps full backdrop blur', () {
    final motion = GlassMotionController(morphEnabled: false);
    addTearDown(motion.dispose);
    const point = Offset(100, 100);
    motion.beginPointer(
      position: point,
      timestamp: Duration.zero,
      target: GlassPointerTarget.main,
    );
    motion.stepForTest(0.05);
    motion.endPointer(
      position: point,
      timestamp: const Duration(milliseconds: 50),
    );
    motion.stepForTest(1);
    expect(motion.backdropBlurSigma, _rest);
    expect(motion.isAtRest, isTrue);
  });

  test('fast drag reduces blur within floor and restores exactly', () {
    final motion = GlassMotionController(morphEnabled: false);
    addTearDown(motion.dispose);
    motion.beginPointer(
      position: Offset.zero,
      timestamp: Duration.zero,
      target: GlassPointerTarget.main,
    );
    motion.movePointer(
      position: const Offset(300, 40),
      timestamp: const Duration(milliseconds: 16),
    );
    motion.stepForTest(0.05);

    final reduced = motion.backdropBlurSigma;
    expect(reduced, lessThan(_rest));
    expect(reduced, greaterThanOrEqualTo(_floor));
    // Quantized to 0.5 steps: shared cached filter, no per-frame allocation.
    expect((reduced * 2).roundToDouble(), reduced * 2);

    motion.endPointer(
      position: const Offset(300, 40),
      timestamp: const Duration(milliseconds: 80),
    );
    motion.stepForTest(1);
    expect(motion.backdropBlurSigma, _rest);
    expect(motion.isAtRest, isTrue);
  });

  test('morph flight reduces blur and parks exact at open rest', () {
    final motion = GlassMotionController();
    addTearDown(motion.dispose);
    motion.requestOpen();
    motion.stepForTest(0.12);
    expect(motion.backdropBlurSigma, lessThan(_rest));
    motion.stepForTest(1);
    motion.stepForTest(1);
    expect(motion.backdropBlurSigma, _rest);
  });

  test('target scale policy: full below threshold, floor at speed', () {
    expect(LiquidBackdropAdapt.targetScale(0), 1.0);
    expect(LiquidBackdropAdapt.targetScale(200), 1.0);
    expect(
      LiquidBackdropAdapt.targetScale(10000),
      moreOrLessEquals(_minScale, epsilon: 1e-9),
    );
    final mid = LiquidBackdropAdapt.targetScale(1500);
    expect(mid, lessThan(1.0));
    expect(mid, greaterThan(_minScale));
  });

  test('segmented lens drops blur on fast drag and restores exactly', () {
    final motion = LiquidSegmentedController(initialIndex: 0, itemCount: 5);
    addTearDown(motion.dispose);
    expect(motion.backdropBlurSigma, _rest);
    motion.beginPointer(
      position: const Offset(10, 27),
      timestamp: Duration.zero,
      itemExtent: 100,
      dragLens: true,
    );
    motion.movePointer(
      position: const Offset(350, 27),
      timestamp: const Duration(milliseconds: 16),
      itemExtent: 100,
    );
    motion.stepForTest(0.05);
    expect(motion.backdropBlurSigma, lessThan(_rest));
    motion.endPointer(
      position: const Offset(350, 27),
      timestamp: const Duration(milliseconds: 60),
      itemExtent: 100,
    );
    motion.stepForTest(1);
    motion.stepForTest(1);
    expect(motion.backdropBlurSigma, _rest);
    expect(motion.isAtRest, isTrue);
  });
}
