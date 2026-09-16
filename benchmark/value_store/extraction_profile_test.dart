import 'package:flutter_test/flutter_test.dart';
import 'package:loon/loon.dart';
import 'iterable_draft.dart';
import 'value_batches_draft.dart';
import 'workloads/extraction.dart' show profileExtraction;

void main() {
  test('toSet preserves extraction semantics and creates an independent set',
      () {
    final store = ValueStore<int?>();
    store.write('', 9);
    store.write('a', 2);
    store.write('a__children__1', 2);
    store.write('a__children__2', null);
    store.write('other', 7);
    for (final path in ['', 'a', 'a__children', 'a__children__2', 'missing']) {
      expect(valuesUnder(store, path).toSet(), store.extractValues(path));
      expect(valuesViaBatches(store, path),
          orderedEquals(valuesUnder(store, path)));
      expect(extractViaBatches(store, path), store.extractValues(path));
    }
    final extracted = valuesUnder(store, 'a').toSet();
    store.delete('a');
    expect(extracted, {2, null});
    expect(valuesUnder(store, 'a'), isEmpty);
    extracted.add(8);
    expect(store.extractValues(), {9, 7});
  });

  test('direct extraction versus lazy traversal accumulated into a set',
      profileExtraction);
}
