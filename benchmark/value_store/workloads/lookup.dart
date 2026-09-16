import 'package:loon/loon.dart';
import '../profile_support.dart';

void profileLookups() {
  final results = ProfileResults();
  const n = 100000;
  final empty = ValueStore<int>();
  final shallow = ValueStore<int>();
  final deep = ValueStore<int>();
  final flat = <String, int>{};
  final shallowPaths = [for (var i = 0; i < n; i++) 'items__$i'];
  final deepPaths = [
    for (var i = 0; i < n; i++) 'orgs__o__teams__t__accounts__a__items__$i'
  ];
  for (var i = 0; i < n; i++) {
    shallow.write(shallowPaths[i], i);
    deep.write(deepPaths[i], i);
    flat[deepPaths[i]] = i;
  }
  const total = n * (n - 1) ~/ 2;
  results.measure('empty/get', () {
    var misses = 0;
    for (final path in deepPaths) {
      if (empty.get(path) == null) misses++;
    }
    return misses;
  }, expected: n, operations: n);
  results.measure('empty/delete', () {
    for (final path in deepPaths) {
      empty.delete(path, recursive: false);
    }
    return empty.isEmpty ? n : 0;
  }, expected: n, operations: n);
  for (final (name, store, paths) in [
    ('shallow/hit', shallow, shallowPaths),
    ('deep/hit', deep, deepPaths),
  ]) {
    results.measure(name, () {
      var sum = 0;
      for (final path in paths) {
        sum += store.get(path)!;
      }
      return sum;
    }, expected: total, operations: n);
  }
  for (final (name, path) in [
    ('deep/early_miss', 'missing__o__teams__t__accounts__a__items__0'),
    ('deep/leaf_miss', 'orgs__o__teams__t__accounts__a__items__missing'),
  ]) {
    results.measure(name, () {
      var misses = 0;
      for (var i = 0; i < n; i++) {
        if (deep.get(path) == null) misses++;
      }
      return misses;
    }, expected: n, operations: n);
  }
  results.measure('deep/hit_flat_map', () {
    var sum = 0;
    for (final path in deepPaths) {
      sum += flat[path]!;
    }
    return sum;
  }, expected: total, operations: n);

// One small collection among many unrelated collections.
  final hierarchy = ValueStore<int>();
  final flatHierarchy = <String, int>{};
  for (var i = 0; i < n; i++) {
    final path = 'accounts__${i ~/ 1000}__items__${i % 1000}';
    hierarchy.write(path, i);
    flatHierarchy[path] = i;
  }
  const target = 'accounts__42__items';
  const subtotal = (42000 + 42999) * 1000 ~/ 2;
  results.measure(
      'collection/value_store',
      () => hierarchy
          .getChildValues(target)!
          .values
          .fold(0, (sum, value) => sum + value),
      expected: subtotal,
      operations: 1000);
  results.measure('collection/flat_map_scan', () {
    var sum = 0;
    for (final entry in flatHierarchy.entries) {
      if (entry.key.startsWith('${target}__')) sum += entry.value;
    }
    return sum;
  }, expected: subtotal, operations: n);

  results.measure(
      'subtree_delete/value_store',
      () {
        hierarchy.delete(target);
        return hierarchy.hasPath(target) ? 0 : 1;
      },
      expected: 1,
      prepare: () {
        for (var i = 42000; i < 43000; i++) {
          hierarchy.write('${target}__${i % 1000}', i);
        }
      });
  results.measure(
      'subtree_delete/flat_map_scan',
      () {
        flatHierarchy.removeWhere((key, _) => key.startsWith('${target}__'));
        return flatHierarchy.length;
      },
      expected: n - 1000,
      prepare: () {
        for (var i = 42000; i < 43000; i++) {
          flatHierarchy['${target}__${i % 1000}'] = i;
        }
      });
  results.save();
}
