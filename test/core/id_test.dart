import 'package:flutter_test/flutter_test.dart';
import 'package:loon/utils/id.dart';

void main() {
  for (final entry in {
    'generateSecureId': generateSecureId,
    'generateFastId': generateFastId,
  }.entries) {
    final name = entry.key;
    final generate = entry.value;

    group(name, () {
      test('generates IDs of the requested length', () {
        expect(generate(), hasLength(21));
        expect(generate(8), hasLength(8));
      });

      test('uses only path-safe characters', () {
        final pathSafeId = RegExp(r'^[-0-9A-Za-z~]+$');

        for (var i = 0; i < 1000; i++) {
          final id = generate();

          expect(id, isNot(contains('__')));
          expect(pathSafeId.hasMatch(id), true, reason: 'id "$id"');
        }
      });
    });
  }
}
