import 'dart:math';
import 'package:flutter_test/flutter_test.dart';
import 'package:loon/loon.dart';
import 'document_values_draft.dart';

void main() {
  test('Scoped document access matches path access across reads and writes',
      () {
    final docs = [
      for (final (parent, id) in [
        ('items', 'a'),
        ('items', 'b'),
        ('items__a', ''),
        ('items', 'a__nested'),
        ('items__a', 'nested'),
        ('items_', 'odd'),
        ('items', '_leading'),
        ('', 'root_child'),
        ('', ''),
        ('other', 'a'),
      ])
        Document<int>(parent, id),
    ];
    for (final seed in [7, 31, 101]) {
      final expected = ValueStore<int>();
      final actual = ValueStore<int>();
      final values = DocumentValues(actual);
      final random = Random(seed);
      // Cache an absent collection, then create it through an unusual handle.
      expect(values.get(docs[0]), isNull);
      expected.write(docs[2].path, 1);
      values.write(docs[2], 1);
      expect(values.get(docs[0]), 1);
      for (var step = 0; step < 600; step++) {
        final doc = docs[random.nextInt(docs.length)];
        final operation = random.nextInt(3);
        if (operation == 0) {
          expected.write(doc.path, step);
          values.write(doc, step);
        } else if (operation == 1) {
          expected.delete(doc.path, recursive: false);
          actual.delete(doc.path, recursive: false);
          values.invalidate();
        } else {
          expect(values.get(doc), expected.get(doc.path),
              reason: 'seed=$seed step=$step path=${doc.path}');
        }
      }
      expect(actual.extract(), expected.extract());
    }
  });
}
