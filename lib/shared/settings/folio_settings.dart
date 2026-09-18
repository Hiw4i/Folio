import 'package:flutter/foundation.dart';

/// Only optional visual effects live here. Scrolling, navigation and document
/// rendering must not depend on the liquid-glass motion preference.
@immutable
class FolioSettings {
  const FolioSettings({
    this.blurEnabled = true,
    this.liquidMotionEnabled = true,
  });

  final bool blurEnabled;
  final bool liquidMotionEnabled;

  FolioSettings copyWith({bool? blurEnabled, bool? liquidMotionEnabled}) =>
      FolioSettings(
        blurEnabled: blurEnabled ?? this.blurEnabled,
        liquidMotionEnabled: liquidMotionEnabled ?? this.liquidMotionEnabled,
      );

  factory FolioSettings.fromJson(Map<String, Object?> json) => FolioSettings(
    blurEnabled: json['blurEnabled'] is bool
        ? json['blurEnabled']! as bool
        : true,
    liquidMotionEnabled: json['liquidMotionEnabled'] is bool
        ? json['liquidMotionEnabled']! as bool
        : true,
  );

  Map<String, Object?> toJson() => <String, Object?>{
    'version': 1,
    'blurEnabled': blurEnabled,
    'liquidMotionEnabled': liquidMotionEnabled,
  };

  @override
  bool operator ==(Object other) =>
      other is FolioSettings &&
      other.blurEnabled == blurEnabled &&
      other.liquidMotionEnabled == liquidMotionEnabled;

  @override
  int get hashCode => Object.hash(blurEnabled, liquidMotionEnabled);
}
