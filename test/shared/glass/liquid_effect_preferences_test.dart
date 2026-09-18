import 'package:flutter/widgets.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:folio/shared/glass/motion/glass_motion_controller.dart';
import 'package:folio/shared/glass/motion/liquid_segmented_controller.dart';

void main() {
  test('disabled motion snaps geometry without disabling open and close', () {
    final motion = GlassMotionController();
    addTearDown(motion.dispose);
    motion.requestOpen();
    motion.stepForTest(0.1);
    expect(motion.morph, greaterThan(0));
    motion.setLiquidMotionEnabled(false);
    expect(motion.morph, 1);
    expect(motion.separation, 1);
    expect(motion.morphVelocity, 0);
    expect(motion.settleWobble, 0);
    expect(motion.backdropScale, 1);
    motion.requestClose();
    expect(motion.morph, 0);
    expect(motion.separation, 0);
    expect(motion.state, GlassInteractionState.idle);
    motion.requestOpen();
    expect(motion.isOpen, isTrue);
  });

  test(
    'disabled fixed control does not stretch on a held or dragged pointer',
    () {
      final motion = GlassMotionController(morphEnabled: false);
      addTearDown(motion.dispose);
      motion.setLiquidMotionEnabled(false);
      motion.beginPointer(
        position: const Offset(20, 20),
        timestamp: Duration.zero,
        target: GlassPointerTarget.main,
      );
      motion.movePointer(
        position: const Offset(120, 60),
        timestamp: const Duration(milliseconds: 40),
      );
      motion.stepForTest(0.5);
      expect(motion.press, 0);
      expect(motion.displacement, Offset.zero);
      expect(motion.pointerVelocity, Offset.zero);
      expect(motion.isPointerDown, isTrue);
      motion.cancelPointer();
      expect(motion.isPointerDown, isFalse);
    },
  );

  test('segmented selection notifies and snaps when motion is disabled', () {
    final motion = LiquidSegmentedController(initialIndex: 0, itemCount: 5);
    addTearDown(motion.dispose);
    motion.setLiquidMotionEnabled(false);
    var notifications = 0;
    motion.addListener(() => notifications++);
    motion.select(4);
    expect(motion.position, 4);
    expect(motion.targetIndex, 4);
    expect(motion.velocity, 0);
    expect(motion.stretch, 0);
    expect(notifications, 1);
    motion.setLiquidMotionEnabled(true);
    motion.select(0);
    expect(motion.position, 4);
    motion.stepForTest(0.05);
    expect(motion.position, lessThan(4));
  });

  test('segmented release safely handles a zero-width layout', () {
    final motion = LiquidSegmentedController(initialIndex: 0, itemCount: 5);
    addTearDown(motion.dispose);
    motion.beginPointer(
      position: const Offset(10, 10),
      timestamp: Duration.zero,
      itemExtent: 50,
      dragLens: true,
    );
    expect(
      motion.endPointer(
        position: const Offset(10, 10),
        timestamp: const Duration(milliseconds: 10),
        itemExtent: 0,
      ),
      0,
    );
    expect(motion.isPointerDown, isFalse);
  });

  testWidgets('idle and disabled controllers do not schedule spring ticks', (
    tester,
  ) async {
    final motion = GlassMotionController(vsync: TestVSync());
    expect(motion.isTicking, isFalse);
    motion.requestOpen();
    expect(motion.isTicking, isTrue);
    motion.setLiquidMotionEnabled(false);
    expect(motion.isTicking, isFalse);
    motion.requestClose();
    expect(motion.isTicking, isFalse);
    await tester.pump(const Duration(seconds: 1));
    expect(motion.morph, 0);
    motion.dispose();
  });

  testWidgets('a pointer cannot override an inherited disabled TickerMode', (
    tester,
  ) async {
    final key = GlobalKey<_MotionHostState>();
    await tester.pumpWidget(
      TickerMode(enabled: false, child: _MotionHost(key: key)),
    );
    final motion = key.currentState!.motion;
    motion.requestOpen();
    await tester.pump();
    await tester.pump(const Duration(milliseconds: 100));
    expect(motion.morph, 0);
    await tester.pumpWidget(
      TickerMode(enabled: true, child: _MotionHost(key: key)),
    );
    await tester.pump(const Duration(milliseconds: 16));
    await tester.pump(const Duration(milliseconds: 16));
    expect(motion.morph, greaterThan(0));
    await tester.pumpWidget(const SizedBox.shrink());
  });
}

class _MotionHost extends StatefulWidget {
  const _MotionHost({super.key});

  @override
  State<_MotionHost> createState() => _MotionHostState();
}

class _MotionHostState extends State<_MotionHost>
    with SingleTickerProviderStateMixin {
  late final GlassMotionController motion;

  @override
  void initState() {
    super.initState();
    motion = GlassMotionController(vsync: this);
  }

  @override
  void dispose() {
    motion.dispose();
    super.dispose();
  }

  @override
  Widget build(BuildContext context) => const SizedBox.shrink();
}
