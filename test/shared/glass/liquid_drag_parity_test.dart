import 'package:flutter_test/flutter_test.dart';
import 'package:folio/shared/glass/glass_motion_controller.dart';

/// Plain buttons run [GlassMotionController] with `morphEnabled: false` —
/// the same code path as a collapsed menu button. This locks the parity:
/// identical pointer input must produce identical press/displacement.
void main() {
  GlassMotionController button() =>
      GlassMotionController(morphEnabled: false);
  GlassMotionController menu() => GlassMotionController();

  void drive(GlassMotionController motion) {
    const start = Offset(200, 200);
    motion.beginPointer(
      position: start,
      timestamp: Duration.zero,
      target: GlassPointerTarget.main,
    );
    motion.stepForTest(0.05);
    motion.movePointer(
      position: start + const Offset(4, 0),
      timestamp: const Duration(milliseconds: 16),
    );
    motion.stepForTest(0.05);
    // Beyond tapSlop: material must follow on both.
    motion.movePointer(
      position: start + const Offset(30, 12),
      timestamp: const Duration(milliseconds: 48),
    );
    motion.stepForTest(0.08);
    motion.movePointer(
      position: start + const Offset(60, 20),
      timestamp: const Duration(milliseconds: 96),
    );
    motion.stepForTest(0.08);
  }

  void expectSameMotion(
    GlassMotionController actual,
    GlassMotionController expected,
  ) {
    expect(actual.press, moreOrLessEquals(expected.press, epsilon: 1e-9));
    expect(
      actual.pressVelocity,
      moreOrLessEquals(expected.pressVelocity, epsilon: 1e-9),
    );
    expect(actual.displacement.dx, moreOrLessEquals(expected.displacement.dx));
    expect(actual.displacement.dy, moreOrLessEquals(expected.displacement.dy));
    expect(
      actual.pointerVelocity.dx,
      moreOrLessEquals(expected.pointerVelocity.dx),
    );
    expect(
      actual.pointerVelocity.dy,
      moreOrLessEquals(expected.pointerVelocity.dy),
    );
    expect(
      actual.lightPosition.dx,
      moreOrLessEquals(expected.lightPosition.dx),
    );
    expect(
      actual.lightPosition.dy,
      moreOrLessEquals(expected.lightPosition.dy),
    );
  }

  test('button drag matches collapsed menu drag frame by frame', () {
    final plain = button();
    final collapsed = menu();
    addTearDown(plain.dispose);
    addTearDown(collapsed.dispose);

    drive(plain);
    drive(collapsed);
    expectSameMotion(plain, collapsed);
    // Deadzone respected on both: 4px move must not drag the material yet.
    expect(plain.displacement.distance, greaterThan(0));

    plain.endPointer(
      position: const Offset(260, 220),
      timestamp: const Duration(milliseconds: 120),
    );
    collapsed.endPointer(
      position: const Offset(260, 220),
      timestamp: const Duration(milliseconds: 120),
    );
    expectSameMotion(plain, collapsed);

    plain.stepForTest(1);
    collapsed.stepForTest(1);
    expectSameMotion(plain, collapsed);
    expect(plain.displacement.distance, lessThan(0.1));
    // Plain button never morphs, menu stays collapsed without open request.
    expect(plain.morph, 0);
    expect(plain.wantsOpen, isFalse);
    expect(collapsed.wantsOpen, isFalse);
    expect(plain.isAtRest, isTrue);
    expect(collapsed.isAtRest, isTrue);
  });

  test('tap on plain button does not request open', () {
    final plain = button();
    addTearDown(plain.dispose);
    const point = Offset(100, 100);
    plain.beginPointer(
      position: point,
      timestamp: Duration.zero,
      target: GlassPointerTarget.main,
    );
    plain.stepForTest(0.03);
    plain.endPointer(
      position: point,
      timestamp: const Duration(milliseconds: 30),
    );
    plain.stepForTest(1);
    expect(plain.wantsOpen, isFalse);
    expect(plain.morph, 0);
    expect(plain.isAtRest, isTrue);
  });
}
