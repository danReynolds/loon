import 'package:flutter_test/flutter_test.dart';
import 'package:loon/utils/id.dart';

void main() {
  // Generated IDs are used as `__`-delimited path segments in the store, so an
  // ID containing the delimiter would be parsed as multiple segments and
  // misplace data. Guard that neither generator can produce one.
  for (final entry in {
    'generateSecureId': generateSecureId,
    'generateFastId': generateFastId,
  }.entries) {
    final name = entry.key;
    final gen = entry.value;

    group(name, () {
      test('never contains the path delimiter', () {
        for (var i = 0; i < 100000; i++) {
          final id = gen();
          expect(id.contains('__'), false, reason: 'id "$id" contains "__"');
        }
      });

      test('produces alphanumeric IDs of the requested length', () {
        final alphanumeric = RegExp(r'^[0-9A-Za-z]+$');
        for (var i = 0; i < 1000; i++) {
          final id = gen();
          expect(id.length, 21);
          expect(alphanumeric.hasMatch(id), true, reason: 'id "$id"');
        }
        expect(gen(8).length, 8);
      });
    });
  }
}
