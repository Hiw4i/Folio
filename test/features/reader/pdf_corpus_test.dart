import 'dart:io';

import 'package:flutter_test/flutter_test.dart';
import 'package:pdfrx/pdfrx.dart';

void main() {
  TestWidgetsFlutterBinding.ensureInitialized();

  String fixture(String name) =>
      File('${Directory.current.path}/test/fixtures/pdf/$name').absolute.path;

  setUpAll(() async {
    Pdfrx.cacheDirectoryPath = Directory.systemTemp.path;
    await pdfrxFlutterInitialize();
  });

  test('long PDF opens progressively and exposes its text layer', () async {
    final document = await PdfDocument.openFile(
      fixture('searchable_long.pdf'),
      useProgressiveLoading: true,
    );
    addTearDown(document.dispose);

    expect(document.pages, hasLength(24));
    final firstPage = await document.pages.first.ensureLoaded();
    final text = await firstPage.loadStructuredText();
    expect(text.fullText, contains('Searchable phrase'));
    final matchCount = RegExp(
      'searchable phrase',
      caseSensitive: false,
    ).allMatches(text.fullText).length;
    expect(matchCount, 2);
  });

  test('rotated page preserves its PDF rotation and geometry', () async {
    final document = await PdfDocument.openFile(fixture('rotated.pdf'));
    addTearDown(document.dispose);

    final page = await document.pages.single.ensureLoaded();
    expect(page.rotation, PdfPageRotation.clockwise90);
    expect(page.height, greaterThan(page.width));
  });

  test('image-only PDF has no searchable text layer', () async {
    final document = await PdfDocument.openFile(fixture('image_only.pdf'));
    addTearDown(document.dispose);

    final page = await document.pages.single.ensureLoaded();
    final text = await page.loadStructuredText();
    expect(text.fullText.trim(), isEmpty);
  });

  test('encrypted PDF reports that a password is required', () async {
    expect(
      () => PdfDocument.openFile(fixture('encrypted.pdf')),
      throwsA(isA<PdfPasswordException>()),
    );
  });

  test('malformed PDF fails with a typed PDF exception', () async {
    expect(
      () => PdfDocument.openFile(fixture('malformed.pdf')),
      throwsA(isA<PdfException>()),
    );
  });
}
