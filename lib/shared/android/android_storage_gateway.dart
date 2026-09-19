import 'dart:async';

import 'package:flutter/services.dart';

class StorageRoot {
  const StorageRoot({required this.path, required this.isRemovable});

  final String path;
  final bool isRemovable;
}

class IncomingDocument {
  const IncomingDocument({
    required this.sourceType,
    required this.value,
    required this.displayName,
    required this.sizeBytes,
    required this.modifiedAt,
    this.createdAt,
    required this.mimeType,
    required this.persistedPermission,
  });

  final String sourceType;
  final String value;
  final String displayName;
  final int sizeBytes;
  final DateTime modifiedAt;
  final DateTime? createdAt;
  final String? mimeType;
  final bool persistedPermission;

  /// Creation time when provided by the platform, else [modifiedAt].
  DateTime get effectiveCreatedAt => createdAt ?? modifiedAt;

  factory IncomingDocument.fromMap(Map<Object?, Object?> map) {
    final modifiedMillis = map['modifiedAtMillis'];
    final createdMillis = map['createdAtMillis'];
    final modifiedAt = modifiedMillis is num
        ? DateTime.fromMillisecondsSinceEpoch(modifiedMillis.toInt())
        : DateTime.now();
    return IncomingDocument(
      sourceType: map['sourceType'] as String? ?? 'uri',
      value: map['value'] as String? ?? '',
      displayName: map['displayName'] as String? ?? 'Untitled',
      sizeBytes: (map['sizeBytes'] as num?)?.toInt() ?? 0,
      modifiedAt: modifiedAt,
      createdAt: createdMillis is num
          ? DateTime.fromMillisecondsSinceEpoch(createdMillis.toInt())
          : null,
      mimeType: map['mimeType'] as String?,
      persistedPermission: map['persistedPermission'] as bool? ?? false,
    );
  }
}

abstract interface class StorageGateway {
  Future<bool> hasAllFilesAccess();

  Future<void> openAllFilesSettings();

  Future<List<StorageRoot>> storageRoots();

  Future<IncomingDocument?> consumeInitialDocument();

  Stream<IncomingDocument> get incomingDocuments;

  Future<IncomingDocument?> requestDocumentAccess({
    required String displayName,
    String? mimeType,
  });
}

class AndroidStorageGateway implements StorageGateway {
  AndroidStorageGateway([
    this._methodChannel = const MethodChannel('folio/storage'),
    this._eventChannel = const EventChannel('folio/intents'),
  ]);

  final MethodChannel _methodChannel;
  final EventChannel _eventChannel;
  Stream<IncomingDocument>? _incomingDocuments;

  @override
  Future<bool> hasAllFilesAccess() async {
    return await _methodChannel.invokeMethod<bool>('getAccessState') ?? false;
  }

  @override
  Future<void> openAllFilesSettings() {
    return _methodChannel.invokeMethod<void>('openAllFilesSettings');
  }

  @override
  Future<List<StorageRoot>> storageRoots() async {
    final roots = await _methodChannel.invokeListMethod<Object?>(
      'getStorageRoots',
    );
    return <StorageRoot>[
      for (final item in roots ?? const <Object?>[])
        if (item is Map && item['path'] is String)
          StorageRoot(
            path: item['path']! as String,
            isRemovable: item['isRemovable'] as bool? ?? false,
          ),
    ];
  }

  @override
  Future<IncomingDocument?> consumeInitialDocument() async {
    final value = await _methodChannel.invokeMethod<Object?>(
      'consumeInitialDocument',
    );
    return _decodeIncoming(value);
  }

  @override
  Stream<IncomingDocument> get incomingDocuments {
    return _incomingDocuments ??= _eventChannel
        .receiveBroadcastStream()
        .map(_decodeIncoming)
        .where((incoming) => incoming != null)
        .cast<IncomingDocument>()
        .asBroadcastStream();
  }

  @override
  Future<IncomingDocument?> requestDocumentAccess({
    required String displayName,
    String? mimeType,
  }) async {
    final value = await _methodChannel.invokeMethod<Object?>(
      'requestDocumentAccess',
      <String, Object?>{'displayName': displayName, 'mimeType': mimeType},
    );
    return _decodeIncoming(value);
  }

  static IncomingDocument? _decodeIncoming(Object? value) {
    if (value is! Map) {
      return null;
    }
    final incoming = IncomingDocument.fromMap(value);
    return incoming.value.isEmpty ? null : incoming;
  }
}
