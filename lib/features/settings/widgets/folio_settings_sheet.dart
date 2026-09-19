import 'package:flutter/material.dart';
import 'package:lucide_flutter/lucide_flutter.dart';

import '../../../shared/glass/surface/glass_panel.dart';
import '../../../shared/settings/folio_settings_controller.dart';
import '../../../shared/settings/folio_settings_scope.dart';
import '../../../shared/theme/folio_theme.dart';
import '../../../shared/widgets/folio_bottom_sheet.dart';

Future<void> showFolioSettingsSheet(BuildContext context) async {
  final controller = FolioSettingsScope.maybeControllerOf(context);
  if (controller == null) {
    return;
  }
  FocusManager.instance.primaryFocus?.unfocus();
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
    return Theme(
      data: ThemeData.dark().copyWith(
        scaffoldBackgroundColor: FolioColors.background,
        colorScheme: const ColorScheme.dark(
          primary: FolioColors.textPrimary,
          surface: FolioColors.background,
        ),
      ),
      child: Material(
        type: MaterialType.transparency,
        child: ConstrainedBox(
          constraints: BoxConstraints(
            maxHeight: MediaQuery.sizeOf(context).height * 0.85,
          ),
          child: GlassPanel(
            borderRadius: FolioBottomSheet.cornerRadius,
            child: SingleChildScrollView(
              padding: const EdgeInsets.fromLTRB(24, 12, 24, 24),
              child: AnimatedBuilder(
                animation: controller,
                builder: (context, child) => Column(
                  mainAxisSize: MainAxisSize.min,
                  crossAxisAlignment: CrossAxisAlignment.start,
                  children: <Widget>[
                    Center(
                      child: Container(
                        width: 34,
                        height: 4,
                        margin: const EdgeInsets.only(bottom: 24),
                        decoration: BoxDecoration(
                          color: const Color(0x55FFFFFF),
                          borderRadius: BorderRadius.circular(2),
                        ),
                      ),
                    ),
                    const Center(
                      child: Text(
                        'SETTINGS',
                        textAlign: TextAlign.center,
                        style: TextStyle(
                          fontFamily: 'Inter',
                          fontSize: 24,
                          fontWeight: FontWeight.w600,
                          color: FolioColors.textPrimary,
                          decoration: TextDecoration.none,
                        ),
                      ),
                    ),
                    const SizedBox(height: 18),
                    const _SettingsSectionHeader(
                      icon: LucideIcons.gauge,
                      title: 'Performance',
                    ),
                    const SizedBox(height: 10),
                    _SettingsCard(
                      children: <Widget>[
                        _SettingsSwitch(
                          switchKey: const ValueKey<String>('settings_blur'),
                          title: 'Blur',
                          description: 'Frosted glass backgrounds',
                          value: controller.settings.blurEnabled,
                          onChanged: controller.setBlurEnabled,
                        ),
                        const _SettingsDivider(),
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
                    const _SettingsSectionHeader(
                      icon: LucideIcons.bookOpen,
                      title: 'Reading',
                    ),
                    const SizedBox(height: 10),
                    _SettingsCard(
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
            ),
          ),
        ),
      ),
    );
  }
}

class _SettingsSectionHeader extends StatelessWidget {
  const _SettingsSectionHeader({required this.icon, required this.title});

  final IconData icon;
  final String title;

  @override
  Widget build(BuildContext context) {
    return Semantics(
      header: true,
      child: Row(
        children: <Widget>[
          Container(
            width: 30,
            height: 30,
            decoration: BoxDecoration(
              color: const Color(0x14FFFFFF),
              borderRadius: BorderRadius.circular(9),
              border: Border.all(color: FolioColors.separator, width: 0.8),
            ),
            child: Icon(icon, size: 15, color: FolioColors.textPrimary),
          ),
          const SizedBox(width: 10),
          Expanded(
            child: Text(
              title,
              style: const TextStyle(
                fontFamily: 'Inter',
                fontSize: 15,
                fontWeight: FontWeight.w600,
                color: FolioColors.textPrimary,
              ),
            ),
          ),
        ],
      ),
    );
  }
}

class _SettingsCard extends StatelessWidget {
  const _SettingsCard({required this.children});

  final List<Widget> children;

  @override
  Widget build(BuildContext context) {
    return DecoratedBox(
      decoration: BoxDecoration(
        color: const Color(0x0DFFFFFF),
        borderRadius: BorderRadius.circular(20),
        border: Border.all(color: FolioColors.separator, width: 0.8),
      ),
      child: Padding(
        padding: const EdgeInsets.fromLTRB(16, 6, 16, 6),
        child: Column(
          crossAxisAlignment: CrossAxisAlignment.start,
          children: children,
        ),
      ),
    );
  }
}

class _SettingsDivider extends StatelessWidget {
  const _SettingsDivider();

  @override
  Widget build(BuildContext context) {
    return const SizedBox(
      height: 0.8,
      width: double.infinity,
      child: ColoredBox(color: FolioColors.separator),
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
