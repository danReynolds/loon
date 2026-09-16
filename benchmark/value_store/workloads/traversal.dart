import 'package:loon/loon.dart';
import '../profile_support.dart';
import '../visitor_draft.dart';

class Row {
  final int id;
  Row(this.id);
}

void profileTraversal() {
  final results = ProfileResults();
  const n = 100000;
  final store = ValueStore<Row>();
  final paths = [
    for (var i = 0; i < n; i++) 'accounts__${i ~/ 1000}__items__${i % 1000}'
  ];
  for (var i = 0; i < n; i++) {
    store.write(paths[i], Row(i));
  }
  for (final (name, path, selected) in [
    ('all', 'accounts', paths),
    ('account', 'accounts__42', paths.sublist(42000, 43000)),
  ]) {
    final expected =
        selected.fold<int>(0, (sum, path) => sum + store.get(path)!.id);
    results.measure('sum/$name/gets',
        () => selected.fold(0, (sum, path) => sum + store.get(path)!.id),
        expected: expected);
    results.measure('sum/$name/extract',
        () => store.extract(path).values.fold(0, (sum, row) => sum + row.id),
        expected: expected);
    results.measure('sum/$name/extract_values',
        () => store.extractValues(path).fold(0, (sum, row) => sum + row.id),
        expected: expected);
    results.measure('sum/$name/visitor', () {
      var sum = 0;
      visitValues(store, path, (row) {
        sum += row.id;
      });
      return sum;
    }, expected: expected);
    results.measure('export/$name/extract', () {
      final rows = store.extract(path).values.toList();
      return rows.fold(0, (sum, row) => sum + row.id);
    }, expected: expected);
    results.measure('export/$name/visitor', () {
      final rows = <Row>[];
      visitValues(store, path, rows.add);
      return rows.fold(0, (sum, row) => sum + row.id);
    }, expected: expected);
  }
  const collection = 'accounts__42__items';
  const subtotal = (42000 + 42999) * 1000 ~/ 2;
  results.measure(
      'sum/collection/child_values',
      () => store
          .getChildValues(collection)!
          .values
          .fold(0, (sum, row) => sum + row.id),
      expected: subtotal);
  results.measure('sum/collection/visitor', () {
    var sum = 0;
    visitValues(store, collection, (row) {
      sum += row.id;
    });
    return sum;
  }, expected: subtotal);
  final ids = {for (var i = 0; i < 10; i++) i * 9999};
  final sparseTotal = ids.reduce((a, b) => a + b);
  results.measure('sum/sparse/gets',
      () => ids.fold(0, (sum, id) => sum + store.get(paths[id])!.id),
      expected: sparseTotal);
  results.measure('sum/sparse/visitor_scan', () {
    var sum = 0;
    visitValues(store, 'accounts', (row) {
      if (ids.contains(row.id)) sum += row.id;
    });
    return sum;
  }, expected: sparseTotal);

  final repeated = ValueStore<int>();
  for (final path in paths) {
    repeated.write(path, 1);
  }
  results.measure('duplicates/count/extract', () => repeated.extract().length,
      expected: n);
  results.measure('duplicates/count/visitor', () {
    var count = 0;
    visitValues(repeated, '', (_) {
      count++;
    });
    return count;
  }, expected: n);
  results.measure('duplicates/distinct/extract_values',
      () => repeated.extractValues().length,
      expected: 1);
  results.measure('duplicates/distinct/visitor_set', () {
    final values = <int>{};
    visitValues(repeated, '', values.add);
    return values.length;
  }, expected: 1);
  results.save();
}
