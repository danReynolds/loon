import 'package:flutter_test/flutter_test.dart';
import 'package:loon/utils/id.dart';

void main() {
  group('IDs', () {
    test('generated IDs do not contain the path delimiter', () {
      for (var i = 0; i < 1000; i++) {
        expect(generateSecureId(), isNot(contains('__')));
        expect(generateFastId(), isNot(contains('__')));
      }
    });
  });
}
