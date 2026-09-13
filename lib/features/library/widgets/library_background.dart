import 'package:flutter/widgets.dart';

import '../../../shared/theme/folio_theme.dart';

class LibraryBackground extends StatelessWidget {
  const LibraryBackground({super.key});

  @override
  Widget build(BuildContext context) {
    return const RepaintBoundary(
      child: DecoratedBox(
        decoration: BoxDecoration(
          color: FolioColors.background,
          gradient: RadialGradient(
            center: Alignment(0.75, -0.65),
            radius: 1.05,
            colors: <Color>[
              Color(0xFF292824),
              Color(0xFF131416),
              FolioColors.background,
            ],
            stops: <double>[0, 0.42, 1],
          ),
        ),
        child: SizedBox.shrink(),
      ),
    );
  }
}
