import 'package:flutter/widgets.dart';

import '../../../shared/glass/liquid_segmented_control.dart';
import '../logic/library_controller.dart';

class LibraryFilterBar extends StatelessWidget {
  const LibraryFilterBar({
    required this.selected,
    required this.onSelected,
    super.key,
  });

  final LibraryFilter selected;
  final ValueChanged<LibraryFilter> onSelected;

  @override
  Widget build(BuildContext context) {
    return Padding(
      padding: const EdgeInsets.symmetric(horizontal: 20),
      child: LiquidSegmentedControl<LibraryFilter>(
        key: const ValueKey<String>('format_filters'),
        selected: selected,
        onSelected: onSelected,
        segments: <LiquidSegment<LibraryFilter>>[
          for (final filter in LibraryFilter.values)
            LiquidSegment<LibraryFilter>(value: filter, label: filter.label),
        ],
      ),
    );
  }
}
