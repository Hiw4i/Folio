import 'package:flutter/gestures.dart';
import 'package:flutter/widgets.dart';

/// An explicit hit-test surface for translucent glass.
///
/// Blur and custom painting do not guarantee that the painted region wins hit
/// testing. This shield keeps taps and drags from reaching content behind a
/// liquid control while leaving gesture handling to its parent controller.
class GlassTouchShield extends StatelessWidget {
  const GlassTouchShield({super.key});

  @override
  Widget build(BuildContext context) {
    return RawGestureDetector(
      behavior: HitTestBehavior.opaque,
      gestures: <Type, GestureRecognizerFactory>{
        EagerGestureRecognizer:
            GestureRecognizerFactoryWithHandlers<EagerGestureRecognizer>(
              EagerGestureRecognizer.new,
              (recognizer) {},
            ),
      },
      child: const SizedBox.expand(),
    );
  }
}

/// Non-competitive hit-test blocker for passive/cluster liquid surfaces
/// (no `onTap`: the surface itself only deforms, inner children may be
/// interactive like the toolbar pill icons).
///
/// Opaque to hit testing, so the traversal stops here and content behind the
/// glass never sees the pointer — but unlike [GlassTouchShield] it joins no
/// gesture arena, so interactive children IN FRONT keep winning their taps.
/// Must be placed BEHIND the content in the [Stack] (not on top of it).
class GlassHitBlocker extends StatelessWidget {
  const GlassHitBlocker({super.key});

  @override
  Widget build(BuildContext context) {
    // No callbacks: pure hit-test wall, paints nothing, wins nothing.
    return const Listener(
      behavior: HitTestBehavior.opaque,
      child: SizedBox.expand(),
    );
  }
}
