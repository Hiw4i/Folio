import 'package:flutter/material.dart';
import 'package:lucide_flutter/lucide_flutter.dart';

import '../../../shared/settings/folio_settings_controller.dart';
import '../../../shared/settings/folio_settings_scope.dart';
import '../../../shared/theme/folio_theme.dart';
import '../../../shared/widgets/folio_bottom_sheet.dart';
import '../../../shared/widgets/folio_sheet_content.dart';

Future<void> showFolioSettingsSheet(BuildContext context) async {
  final controller = FolioSettingsScope.maybeControllerOf(context);
  if (controller == null) {
    return;
  }
  await FolioBottomSheet.show<void>(
    context: context,
    builder: (context) => FolioSettingsSheet(controller: controller),
  );
}

class FolioSettingsSheet extends StatelessWidget {
  const FolioSettingsSheet({required this.controller, super.key});

  final FolioSettingsController controller;

  @override
  Widget build(BuildContext context) {
    return FolioSheetContent(
      title: 'Settings',
      child: AnimatedBuilder(
        animation: controller,
        builder: (context, child) => Column(
          mainAxisSize: MainAxisSize.min,
          crossAxisAlignment: CrossAxisAlignment.start,
          children: <Widget>[
            const FolioSheetSectionHeader(
              icon: LucideIcons.gauge,
              title: 'Performance',
            ),
            const SizedBox(height: 10),
            FolioSheetCard(
              children: <Widget>[
                _SettingsSwitch(
                  switchKey: const ValueKey<String>('settings_blur'),
                  title: 'Blur',
                  description: 'Frosted glass backgrounds',
                  value: controller.settings.blurEnabled,
                  onChanged: controller.setBlurEnabled,
                ),
                const FolioSheetDivider(),
                _SettingsSwitch(
                  switchKey: const ValueKey<String>(
                    'settings_liquid_motion',
                  ),
                  title: 'Liquid motion',
                  description: 'Stretching and spring effects',
                  value: controller.settings.liquidMotionEnabled,
                  onChanged: controller.setLiquidMotionEnabled,
                ),
              ],
            ),
            const SizedBox(height: 22),
            const FolioSheetSectionHeader(
              icon: LucideIcons.bookOpen,
              title: 'Reading',
            ),
            const SizedBox(height: 10),
            FolioSheetCard(
              children: <Widget>[
                _SettingsSwitch(
                  switchKey: const ValueKey<String>(
                    'settings_show_navigation_on_scroll_up',
                  ),
                  title: 'Navigation follows scroll',
                  description:
                      'Hide on scroll down, reveal on scroll up. '
                      'Taps always toggle them.',
                  value: controller.settings.showNavigationOnScrollUp,
                  onChanged: controller.setShowNavigationOnScrollUp,
                ),
              ],
            ),
            if (controller.hasSaveError) ...<Widget>[
              const SizedBox(height: 12),
              const Text(
                'Could not save settings. Changes still apply for this session.',
                style: FolioText.metadata,
              ),
              TextButton(
                onPressed: controller.retrySave,
                child: const Text('Retry'),
              ),
            ],
          ],
        ),
      ),
    );
  }
}

class _SettingsSwitch extends StatelessWidget {
  const _SettingsSwitch({
    required this.switchKey,
    required this.title,
    required this.description,
    required this.value,
    required this.onChanged,
  });

  final Key switchKey;
  final String title;
  final String description;
  final bool value;
  final ValueChanged<bool> onChanged;

  @override
  Widget build(BuildContext context) {
    return Padding(
      padding: const EdgeInsets.symmetric(vertical: 10),
      child: Row(
        children: <Widget>[
          Expanded(
            child: Column(
              crossAxisAlignment: CrossAxisAlignment.start,
              children: <Widget>[
                Text(title, style: FolioText.body),
                const SizedBox(height: 3),
                Text(description, style: FolioText.metadata),
              ],
            ),
          ),
          const SizedBox(width: 16),
          Semantics(
            label: title,
            child: Switch.adaptive(
              key: switchKey,
              value: value,
              onChanged: onChanged,
              activeTrackColor: const Color(0xFFD0D0CD),
              activeThumbColor: const Color(0xFF202123),
            ),
          ),
        ],
      ),
    );
  }
}
