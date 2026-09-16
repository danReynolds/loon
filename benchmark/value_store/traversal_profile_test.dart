import 'package:flutter_test/flutter_test.dart';
import 'package:loon/loon.dart';
import 'visitor_draft.dart';
import 'workloads/traversal.dart' show profileTraversal;

void main() {
  test('visitor semantics include own values, duplicates, nulls and root', () {
    final store = ValueStore<int?>();
    store.write('', 9);
    store.write('a', 2);
    store.write('a__children__1', 2);
    store.write('a__children__2', null);
    store.write('other', 7);
    final actual = <int?>[];
    visitValues(store, 'a', actual.add);
    expect(actual, unorderedEquals([2, 2, null]));
    actual.clear();
    visitValues(store, '', actual.add);
    expect(actual, unorderedEquals([9, 2, 2, null, 7]));
    actual.clear();
    visitValues(store, 'missing', actual.add);
    expect(actual, isEmpty);
  });

  test('aggregate, export, sparse lookup and distinct-value traversal',
      profileTraversal);
}
