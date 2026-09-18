import 'package:flutter/material.dart';

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
                    const Text(
                      'Settings',
                      style: TextStyle(
                        fontFamily: 'Inter',
                        fontSize: 24,
                        fontWeight: FontWeight.w600,
                        color: FolioColors.textPrimary,
                        decoration: TextDecoration.none,
                      ),
                    ),
                    const SizedBox(height: 18),
                    _EffectSwitch(
                      switchKey: const ValueKey<String>('settings_blur'),
                      title: 'Blur',
                      description: 'Frosted glass backgrounds',
                      value: controller.settings.blurEnabled,
                      onChanged: controller.setBlurEnabled,
                    ),
                    const SizedBox(height: 8),
                    _EffectSwitch(
                      switchKey: const ValueKey<String>(
                        'settings_liquid_motion',
                      ),
                      title: 'Liquid motion',
                      description: 'Stretching and spring effects',
                      value: controller.settings.liquidMotionEnabled,
                      onChanged: controller.setLiquidMotionEnabled,
                    ),
                    const SizedBox(height: 18),
                    const Text(
                      'Turn off effects to reduce graphics load.',
                      style: FolioText.metadata,
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

class _EffectSwitch extends StatelessWidget {
  const _EffectSwitch({
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
    return Row(
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
    );
  }
}
