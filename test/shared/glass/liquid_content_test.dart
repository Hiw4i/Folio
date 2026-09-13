import 'package:flutter_test/flutter_test.dart';
import 'package:folio/shared/glass/widgets/liquid_content.dart';

void main() {
  test('content blur filters are cached in tenth-pixel buckets', () {
    final first = LiquidContent.softeningFilterFor(1.01);
    final sameBucket = LiquidContent.softeningFilterFor(1.04);
    final nextBucket = LiquidContent.softeningFilterFor(1.06);

    expect(identical(first, sameBucket), isTrue);
    expect(identical(first, nextBucket), isFalse);
  });
}
