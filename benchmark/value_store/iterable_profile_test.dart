import 'package:flutter_test/flutter_test.dart';
import 'package:loon/loon.dart';
import 'iterable_draft.dart';
import 'visitor_draft.dart';
import 'workloads/iterable.dart' show profileIterable;

void main() {
  test('lazy iteration preserves values and restarts against the current store',
      () {
    final store = ValueStore<int?>();
    final lazy = valuesUnder(store, 'a');
    store.write('', 9);
    store.write('a', 2);
    store.write('a__children__1', 2);
    store.write('a__children__2', null);
    store.write('other', 7);
    for (final path in ['', 'a', 'a__children', 'missing']) {
      final expected = <int?>[];
      visitValues(store, path, expected.add);
      expect(valuesUnder(store, path), orderedEquals(expected));
    }
    expect(lazy, orderedEquals([2, 2, null]));
    var visited = 0;
    expect(
        lazy.map((value) {
          visited++;
          return value;
        }).take(1),
        orderedEquals([2]));
    expect(visited, 1);
    store.clear();
    store.write('a', 5);
    expect(lazy, orderedEquals([5]));
  });

  test('callback versus recursive sync generator', profileIterable);
}
