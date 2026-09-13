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

  test('seekable content URI exposes bounded PDF range reads', () async {
    final methods = <String>[];
    TestDefaultBinaryMessengerBinding.instance.defaultBinaryMessenger
        .setMockMethodCallHandler(channel, (call) async {
          methods.add(call.method);
          return switch (call.method) {
            'preparePdfSource' => <String, Object?>{
              'kind': 'range',
              'sessionId': 'pdf-42',
              'length': 4096,
            },
            'readPdfRange' => Uint8List.fromList(<int>[7, 8, 9]),
            'closePdfSource' => null,
            _ => throw MissingPluginException(),
          };
        });
    final source = DeviceDocumentContentSource(methodChannel: channel);

    final prepared = await source.preparePdf(
      const UriDocumentSource('content://provider/document/42'),
    );

    expect(prepared, isA<PreparedPdfRandomAccess>());
    expect(prepared.length, 4096);
    final range = prepared as PreparedPdfRandomAccess;
    expect(await range.readRange(128, 3), <int>[7, 8, 9]);
    await range.close();
    expect(methods, <String>[
      'preparePdfSource',
      'readPdfRange',
      'closePdfSource',
    ]);
  });

  test('non-seekable content URI uses a disposable session file', () async {
    var closed = false;
    TestDefaultBinaryMessengerBinding.instance.defaultBinaryMessenger
        .setMockMethodCallHandler(channel, (call) async {
          if (call.method == 'preparePdfSource') {
            return <String, Object?>{
              'kind': 'file',
              'sessionId': 'pdf-temp',
              'path': '/cache/folio_pdf_sessions/pdf-temp.pdf',
              'length': 512,
            };
          }
          if (call.method == 'closePdfSource') {
            closed = true;
            return null;
          }
          throw MissingPluginException();
        });
    final source = DeviceDocumentContentSource(methodChannel: channel);

    final prepared = await source.preparePdf(
      const UriDocumentSource('content://provider/document/pipe'),
    );

    expect(prepared, isA<PreparedPdfFile>());
    expect((prepared as PreparedPdfFile).path, contains('pdf-temp.pdf'));
    await prepared.close();
    expect(closed, isTrue);
  });
}
