import 'package:flutter/widgets.dart';

/// Paints constant, non-interactive fades over the top and bottom of a
/// scrollable viewport without placing a [ShaderMask] around that viewport.
///
/// The fades deliberately remain visible at both scroll extents. They are
/// separate static layers, so scrolling does not rebuild or repaint them.
class ScrollEdgeFade extends StatelessWidget {
  const ScrollEdgeFade({
    required this.child,
    required this.color,
    this.fraction = 0.13,
    super.key,
  }) : assert(fraction > 0 && fraction <= 0.5);

  final Widget child;
  final Color color;
  final double fraction;

  static const Key topKey = ValueKey<String>('scroll_edge_fade_top');
  static const Key bottomKey = ValueKey<String>('scroll_edge_fade_bottom');

  @override
  Widget build(BuildContext context) {
    return LayoutBuilder(
      builder: (context, constraints) {
        final height = constraints.maxHeight * fraction;
        return Stack(
          fit: StackFit.expand,
          children: <Widget>[
            child,
            Positioned(
              key: topKey,
              top: 0,
              left: 0,
              right: 0,
              height: height,
              child: RepaintBoundary(
                child: IgnorePointer(
                  child: DecoratedBox(
                    decoration: BoxDecoration(
                      gradient: LinearGradient(
                        begin: Alignment.topCenter,
                        end: Alignment.bottomCenter,
                        colors: <Color>[color, color.withValues(alpha: 0)],
                      ),
                    ),
                  ),
                ),
              ),
            ),
            Positioned(
              key: bottomKey,
              bottom: 0,
              left: 0,
              right: 0,
              height: height,
              child: RepaintBoundary(
                child: IgnorePointer(
                  child: DecoratedBox(
                    decoration: BoxDecoration(
                      gradient: LinearGradient(
                        begin: Alignment.bottomCenter,
                        end: Alignment.topCenter,
                        colors: <Color>[color, color.withValues(alpha: 0)],
                      ),
                    ),
                  ),
                ),
              ),
            ),
          ],
        );
      },
    );
  }
}
