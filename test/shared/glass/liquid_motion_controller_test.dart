import 'package:flutter_test/flutter_test.dart';
import 'package:folio/shared/glass/core/liquid_motion_controller.dart';

void main() {
  testWidgets('does not notify when a frame has no fixed simulation step', (
    tester,
  ) async {
    final motion = _CountingMotion(vsync: TestVSync());
    var notifications = 0;
    motion.addListener(() => notifications += 1);

    await tester.pump();
    await tester.pump(const Duration(milliseconds: 4));
    expect(notifications, 0);

    await tester.pump(const Duration(milliseconds: 5));
    expect(motion.steps, 1);
    expect(notifications, 1);

    motion.dispose();
    await tester.pump();
  });
}

class _CountingMotion extends LiquidMotionController {
  _CountingMotion({required super.vsync});

  int steps = 0;

  @override
  bool get isAtRest => false;

  @override
  void integrate(double dt) {
    steps += 1;
  }
}
