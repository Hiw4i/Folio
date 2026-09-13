import 'package:flutter/services.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:folio/features/library/data/document_entry.dart';
import 'package:folio/features/reader/data/document_content_source.dart';

void main() {
  TestWidgetsFlutterBinding.ensureInitialized();
  const channel = MethodChannel('folio/test-content');

  tearDown(() {
    TestDefaultBinaryMessengerBinding.instance.defaultBinaryMessenger
        .setMockMethodCallHandler(channel, null);
  });

  test(
    'content URI bytes are read through the narrow Android bridge',
    () async {
      MethodCall? received;
      TestDefaultBinaryMessengerBinding.instance.defaultBinaryMessenger
          .setMockMethodCallHandler(channel, (call) async {
            received = call;
            return Uint8List.fromList(<int>[1, 2, 3]);
          });
      final source = DeviceDocumentContentSource(methodChannel: channel);

      final result = await source.read(
        const UriDocumentSource('content://provider/document/42'),
      );

      expect(result, <int>[1, 2, 3]);
      expect(received?.method, 'readContentUri');
      expect(
        (received?.arguments as Map<Object?, Object?>)['uri'],
        'content://provider/document/42',
      );
    },
  );

  test('expired URI permission becomes a typed denied failure', () async {
    TestDefaultBinaryMessengerBinding.instance.defaultBinaryMessenger
        .setMockMethodCallHandler(channel, (call) async {
          throw PlatformException(code: 'access_denied');
        });
    final source = DeviceDocumentContentSource(methodChannel: channel);

    expect(
      () => source.read(const UriDocumentSource('content://provider/expired')),
      throwsA(
        isA<DocumentReadException>().having(
          (error) => error.kind,
          'kind',
          DocumentReadFailureKind.denied,
        ),
      ),
    );
  });
}
