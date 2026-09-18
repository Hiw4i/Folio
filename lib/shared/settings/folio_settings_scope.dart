import 'package:flutter/widgets.dart';

import 'folio_settings.dart';
import 'folio_settings_controller.dart';

/// Above the Navigator so pushed readers, menus and sheets share preferences.
/// Optional for isolated controls/tests: the original visual mode is default.
class FolioSettingsScope extends InheritedNotifier<FolioSettingsController> {
  const FolioSettingsScope({
    required FolioSettingsController controller,
    required super.child,
    super.key,
  }) : super(notifier: controller);

  static FolioSettingsController? maybeControllerOf(BuildContext context) =>
      context
          .dependOnInheritedWidgetOfExactType<FolioSettingsScope>()
          ?.notifier;

  static FolioSettings settingsOf(BuildContext context) =>
      maybeControllerOf(context)?.settings ?? const FolioSettings();

  static bool blurEnabledOf(BuildContext context) =>
      settingsOf(context).blurEnabled;

  static bool liquidMotionEnabledOf(BuildContext context) =>
      settingsOf(context).liquidMotionEnabled;
}
