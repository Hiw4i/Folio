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
