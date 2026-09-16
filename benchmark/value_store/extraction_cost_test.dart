import 'dart:math';
import 'package:flutter_test/flutter_test.dart';
import 'package:loon/loon.dart';
import 'extraction_draft.dart';
import 'workloads/extraction_cost.dart';

void main() {
  test(
      'extraction candidates preserve snapshots, nulls, own values and equality',
      () {
    final first = EqualEntry(1);
    final store = ValueStore<EqualEntry?>();
    store.write('', EqualEntry(9));
    store.write('a', first);
    store.write('a__children__1', EqualEntry(1));
    store.write('a__children__2', null);
    store.write('other', EqualEntry(7));
    for (final extract in [
      extractForEach<EqualEntry?>,
      extractDirectLoop<EqualEntry?>,
      extractUnordered<EqualEntry?>
    ]) {
      for (final path in [
        '',
        'a',
        'a__children',
        'a__children__2',
        'missing'
      ]) {
        expect(extract(store, path), store.extractValues(path));
      }
      final result = extract(store, 'a');
      expect(identical(result.lookup(EqualEntry(1)), first), isTrue);
      result.add(EqualEntry(42));
      expect(store.extractValues('a').contains(EqualEntry(42)), isFalse);
    }
    final snapshot = extractForEach(store, 'a');
    store.delete('a');
    expect(snapshot, {first, null});
  });

  test('ordered candidates match extraction across random writes and deletion',
      () {
    for (var seed = 0; seed < 5; seed++) {
      final random = Random(seed);
      final store = ValueStore<int?>();
      final model = <String, int?>{};
      for (var step = 0; step < 200; step++) {
        final path =
            'a${random.nextInt(5)}__b${random.nextInt(8)}__c${random.nextInt(4)}';
        if (random.nextBool()) {
          final value = random.nextInt(5) == 0 ? null : random.nextInt(15);
          store.write(path, value);
          model[path] = value;
        } else {
          final prefix = path.split('__').take(2).join('__');
          store.delete(prefix);
          model.removeWhere(
              (key, _) => key == prefix || key.startsWith('${prefix}__'));
        }
        for (final prefix in ['', 'a0', 'a1__b2', path, 'missing']) {
          final expected = model.entries
              .where((entry) =>
                  prefix.isEmpty ||
                  entry.key == prefix ||
                  entry.key.startsWith('${prefix}__'))
              .map((entry) => entry.value)
              .toSet();
          for (final extract in [
            extractForEach<int?>,
            extractDirectLoop<int?>
          ]) {
            final result = extract(store, prefix);
            expect(result, expected);
            expect(result.toList(), store.extractValues(prefix).toList());
          }
        }
      }
    }
  });

  test('extraction cost decomposition', profileExtractionCost);
}
