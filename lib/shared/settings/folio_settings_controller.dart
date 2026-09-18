import 'dart:async';

import 'package:flutter/foundation.dart';

import 'folio_settings.dart';
import 'folio_settings_store.dart';

class FolioSettingsController extends ChangeNotifier {
  FolioSettingsController({required this._store});

  final FolioSettingsStore _store;
  FolioSettings _settings = const FolioSettings();
  Future<void>? _loading;
  Future<void>? _saving;
  bool _blurChanged = false;
  bool _motionChanged = false;
  bool _saveRequested = false;
  bool _disposed = false;
  Object? _saveError;

  FolioSettings get settings => _settings;
  bool get hasSaveError => _saveError != null;

  Future<void> load() => _loading ??= _load();

  Future<void> _load() async {
    try {
      final stored = await _store.load();
      // A slow disk read must never undo an interaction already made by the
      // user. Merge untouched fields instead of discarding all stored values.
      final next = stored.copyWith(
        blurEnabled: _blurChanged ? _settings.blurEnabled : null,
        liquidMotionEnabled: _motionChanged
            ? _settings.liquidMotionEnabled
            : null,
      );
      if (next != _settings) {
        _settings = next;
        _notify();
      }
    } catch (error) {
      // Missing/corrupt storage is not a reason to block the first app frame.
      debugPrint('Folio settings could not be loaded: $error');
    }
  }

  void setBlurEnabled(bool enabled) {
    if (_disposed || enabled == _settings.blurEnabled) {
      return;
    }
    _blurChanged = true;
    _settings = _settings.copyWith(blurEnabled: enabled);
    _changed();
  }

  void setLiquidMotionEnabled(bool enabled) {
    if (_disposed || enabled == _settings.liquidMotionEnabled) {
      return;
    }
    _motionChanged = true;
    _settings = _settings.copyWith(liquidMotionEnabled: enabled);
    _changed();
  }

  void _changed() {
    _saveError = null;
    _notify();
    _scheduleSave();
  }

  void retrySave() {
    if (!_disposed) {
      _scheduleSave();
    }
  }

  void _scheduleSave() {
    _saveRequested = true;
    _saving ??= _drainWrites().whenComplete(() {
      _saving = null;
      // A change may arrive in the microtask between draining and completion.
      if (_saveRequested) {
        _scheduleSave();
      }
    });
  }

  Future<void> _drainWrites() async {
    await load();
    // One writer, latest-value coalescing. A rapid pair of switches cannot
    // race two temporary files or leave an older preference on disk.
    while (_saveRequested) {
      _saveRequested = false;
      final snapshot = _settings;
      try {
        await _store.save(snapshot);
        _saveError = null;
      } catch (error) {
        _saveError = error;
        debugPrint('Folio settings could not be saved: $error');
      }
      _notify();
    }
  }

  /// Also useful when the app is backgrounded; pending writes outlive the UI.
  Future<void> flush() async {
    while (_saving != null) {
      await _saving;
    }
  }

  void _notify() {
    if (!_disposed) {
      notifyListeners();
    }
  }

  @override
  void dispose() {
    _disposed = true;
    super.dispose();
  }
}
