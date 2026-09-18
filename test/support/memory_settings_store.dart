import 'package:folio/shared/settings/folio_settings.dart';
import 'package:folio/shared/settings/folio_settings_store.dart';

class MemorySettingsStore implements FolioSettingsStore {
  MemorySettingsStore([this.value = const FolioSettings()]);

  FolioSettings value;
  int saves = 0;

  @override
  Future<FolioSettings> load() async => value;

  @override
  Future<void> save(FolioSettings settings) async {
    value = settings;
    saves++;
  }
}
