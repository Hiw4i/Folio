import 'package:flutter_test/flutter_test.dart';
import 'package:folio/features/library/data/in_memory_library_repository.dart';
import 'package:folio/features/library/logic/library_controller.dart';

void main() {
  late LibraryController controller;

  setUp(() {
    controller = LibraryController(
      repository: InMemoryLibraryRepository.demo(),
    );
  });

  tearDown(() => controller.dispose());

  test(
    'shows recent documents separately and sorts the rest by name',
    () async {
      await controller.load();

      expect(controller.recentDocuments.length, 3);
      expect(controller.recentDocuments.first.name, 'Product principles.pdf');
      expect(controller.regularDocuments.first.name, 'Annual report.pdf');
      expect(
        controller.regularDocuments.map((document) => document.id).toSet(),
        isNot(containsAll(controller.recentDocuments.map((item) => item.id))),
      );
    },
  );

  test('filters before applying case-insensitive filename search', () async {
    await controller.load();

    controller.selectFilter(LibraryFilter.powerPoint);
    expect(
      controller.regularDocuments.map((document) => document.name),
      containsAll(<String>['Launch review.pptx', 'Roadmap.pptx']),
    );

    controller.updateQuery('ROAD');
    expect(controller.regularDocuments.single.name, 'Roadmap.pptx');
    expect(controller.recentDocuments, isEmpty);
  });

  test('opening a document moves it to the front of Recent', () async {
    await controller.load();
    final document = controller.regularDocuments.first;

    await controller.open(document);

    expect(controller.recentDocuments.first.id, document.id);
  });
}
