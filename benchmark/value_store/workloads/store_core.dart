import 'package:loon/src/store/store.dart';
import '../profile_support.dart';

/// Store-only workloads shared by the Dart isolation runner and Flutter hosts.
/// Paths are prepared once; mutation setup and result checks stay outside timing.
void profileStoreCore() {
  final results = ProfileResults();
  final filter = profileSetting('PROFILE_FILTER');
  final selected = filter == null ? null : RegExp(filter);
  const n = 20000;
  const repeats = 100000;
  const total = n * (n - 1) ~/ 2;
  final shallowPaths = [for (var i = 0; i < n; i++) 'items__$i'];
  final deepPaths = [
    for (var i = 0; i < n; i++) 'orgs__o__teams__t__accounts__a__items__$i'
  ];

  void measure<R>(String name, R Function() action, bool Function(R) validate,
      {void Function()? prepare, int operations = 1}) {
    if (selected != null && !selected.hasMatch(name)) return;
    final samples = <int>[];
    for (final record in samplePhases()) {
      prepare?.call();
      final watch = Stopwatch()..start();
      final result = action();
      watch.stop();
      check(validate(result), 'store_core/$name');
      if (record) samples.add(watch.elapsedMicroseconds);
    }
    results.add(name, samples, {'operations': operations});
  }

  final empty = ValueStore<int>();
  measure('empty/get', () {
    var missing = 0;
    for (var i = 0; i < repeats; i++) {
      if (empty.get('missing__child') == null) missing++;
    }
    return missing;
  }, (missing) => missing == repeats, operations: repeats);

  for (final (shape, paths) in [
    ('shallow', shallowPaths),
    ('deep', deepPaths)
  ]) {
    final store = ValueStore<int>();
    void seed() {
      store.clear();
      for (var i = 0; i < n; i++) {
        store.write(paths[i], i);
      }
    }

    seed();
    final prefix = paths.first.substring(0, paths.first.lastIndexOf('__'));
    measure('$shape/get', () {
      var sum = 0;
      for (final path in paths) {
        sum += store.get(path)!;
      }
      return sum;
    }, (sum) => sum == total, operations: n);
    for (final (kind, path) in [
      ('value', paths.last),
      ('node', prefix),
      ('early_miss', 'missing__${prefix}__0'),
      ('late_miss', '${prefix}__missing'),
    ]) {
      if (kind.endsWith('miss')) {
        measure('$shape/get_$kind', () {
          var missing = 0;
          for (var i = 0; i < repeats; i++) {
            if (store.get(path) == null) missing++;
          }
          return missing;
        }, (missing) => missing == repeats, operations: repeats);
      }
      measure('$shape/has_path_$kind', () {
        var hits = 0;
        for (var i = 0; i < repeats; i++) {
          if (store.hasPath(path)) hits++;
        }
        return hits;
      }, (hits) => hits == (kind.endsWith('miss') ? 0 : repeats),
          operations: repeats);
    }
    measure('$shape/child_values', () {
      var count = 0;
      for (var i = 0; i < repeats; i++) {
        count += store.getChildValues(prefix)!.length;
      }
      return count;
    }, (count) => count == repeats * n, operations: repeats);
    measure('$shape/nearest_leaf', () {
      var sum = 0;
      for (final path in paths) {
        sum += store.getNearest(path)!.$2;
      }
      return sum;
    }, (sum) => sum == total, operations: n);
    measure('$shape/extract_single', () {
      var sum = 0;
      for (final path in paths) {
        sum += store.extractValues(path).single;
      }
      return sum;
    }, (sum) => sum == total, operations: n);
    measure('$shape/write_new', () {
      for (var i = 0; i < n; i++) {
        store.write(paths[i], i);
      }
      return store;
    },
        (store) =>
            store.extractValues().length == n && store.get(paths.last) == n - 1,
        prepare: store.clear,
        operations: n);
    measure('$shape/overwrite', () {
      for (var i = 0; i < n; i++) {
        store.write(paths[i], i + 1);
      }
      return store;
    }, (store) => store.get(paths.first) == 1 && store.get(paths.last) == n,
        prepare: seed, operations: n);
    measure('$shape/delete_leaves', () {
      for (final path in paths) {
        store.delete(path);
      }
      return store.isEmpty;
    }, (empty) => empty, prepare: seed, operations: n);
  }

  final widePaths = [for (var i = 0; i < n; i++) 'accounts__${i}__items__0'];
  final wide = ValueStore<int>();
  void seedWide() {
    for (var i = 0; i < n; i++) {
      wide.write(widePaths[i], i);
    }
  }

  measure('wide/write_new', () {
    seedWide();
    return wide;
  }, (store) => store.extractValues().length == n,
      prepare: wide.clear, operations: n);
  // Every read is under a different parent, so none can reuse the last parent node.
  measure(
      'wide/get',
      () {
        var sum = 0;
        for (final path in widePaths) {
          sum += wide.get(path)!;
        }
        return sum;
      },
      (sum) => sum == total,
      prepare: () {
        wide.clear();
        seedWide();
      },
      operations: n);
  measure('wide/delete_leaves', () {
    for (final path in widePaths) {
      wide.delete(path);
    }
    return wide.isEmpty;
  }, (empty) => empty, prepare: seedWide, operations: n);

  final refs = ValueRefStore<int>();
  void seedRefs() {
    for (var i = 0; i < n; i++) {
      refs.write(deepPaths[i], i % 64);
    }
  }

  measure('refs/write_shared', () {
    seedRefs();
    return refs;
  },
      (store) =>
          store.getRefs()!.length == 64 &&
          store.getRefs()!.values.fold(0, (sum, count) => sum + count) == n,
      prepare: refs.clear,
      operations: n);
  measure('refs/delete_shared', () {
    for (final path in deepPaths) {
      refs.delete(path);
    }
    return refs.isEmpty;
  }, (empty) => empty, prepare: seedRefs, operations: n);
  measure('refs/overwrite_shared', () {
    for (var i = 0; i < n; i++) {
      refs.write(deepPaths[i], (i + 1) % 64);
    }
    return refs;
  },
      (store) =>
          store.get(deepPaths.first) == 1 &&
          store.getRefs()!.length == 64 &&
          store.getRefs()!.values.fold(0, (sum, count) => sum + count) == n,
      prepare: seedRefs,
      operations: n);
  measure('refs/delete_subtree', () {
    refs.delete('orgs__o__teams__t__accounts__a__items');
    return refs.isEmpty;
  }, (empty) => empty, prepare: seedRefs);

  // IDs can be much longer than collection names, and Dart supports both
  // one-byte and two-byte strings. Keep delimiter optimizations honest across
  // those shapes, including non-overlapping runs of underscores.
  const pathCount = 10000;
  const pathTotal = pathCount * (pathCount - 1) ~/ 2;
  final longSegment = 'x' * 128;
  for (final (shape, prefix, idPrefix) in [
    (
      'uuid',
      'accounts__17cf805b-9f50-4fcf-b33a-2589a4c09fca__items',
      '117aea65-c56c-4950-bf57-'
    ),
    ('long_segments', '${longSegment}__${longSegment}__items', longSegment),
    ('unicode', '組織💙__北區__帳戶__項目', '文書🎈'),
    ('underscores', 'org_units__alpha_beta___branch____items', '_entry_'),
  ]) {
    final paths = [
      for (var i = 0; i < pathCount; i++) '${prefix}__$idPrefix$i'
    ];
    final store = ValueStore<int>();
    void seed() {
      for (var i = 0; i < pathCount; i++) {
        store.write(paths[i], i);
      }
    }

    seed();
    measure('path_shape/$shape/get', () {
      var sum = 0;
      for (final path in paths) {
        sum += store.get(path)!;
      }
      return sum;
    }, (sum) => sum == pathTotal, operations: pathCount);
    measure('path_shape/$shape/write_new', () {
      seed();
      return store;
    }, (store) => store.extractValues().length == pathCount,
        prepare: store.clear, operations: pathCount);
  }

  final ancestors = ValueStore<int>();
  final chain = [for (var i = 0; i < 12; i++) 'level$i'];
  for (var i = 0; i < chain.length; i++) {
    ancestors.write(chain.take(i + 1).join('__'), i);
  }
  ancestors.write('', -1);
  final full = chain.join('__');
  for (final (name, path, expected) in [
    ('leaf', full, 11),
    ('fallback', '${full}__missing__more', 11),
    ('root', 'missing__more', -1),
  ]) {
    measure('ancestors/nearest_$name', () {
      var sum = 0;
      for (var i = 0; i < n; i++) {
        sum += ancestors.getNearest(path)!.$2;
      }
      return sum;
    }, (sum) => sum == n * expected, operations: n);
  }
  final matchedAncestor = chain.take(4).join('__');
  measure('ancestors/match', () {
    var count = 0;
    for (var i = 0; i < n; i++) {
      if (ancestors.getNearestMatch(full, 3) == matchedAncestor) count++;
    }
    return count;
  }, (count) => count == n, operations: n);
  measure('ancestors/extract', () {
    var count = 0;
    for (var i = 0; i < n; i++) {
      count += ancestors.extractParentPath(full).length;
    }
    return count;
  }, (count) => count == n * 13, operations: n);

  for (final shape in [
    'flat',
    'buckets',
    'singletons',
    'deep_nodes',
    'duplicates'
  ]) {
    final store = ValueStore<int>();
    final count = shape == 'flat' || shape == 'duplicates' ? 100000 : n;
    for (var i = 0; i < count; i++) {
      final path = switch (shape) {
        'flat' || 'duplicates' => 'items__$i',
        'buckets' => 'accounts__${i ~/ 1000}__items__${i % 1000}',
        'singletons' => 'accounts__${i}__value',
        _ => 'accounts__${i}__a__b__c__d__e__value',
      };
      store.write(path, shape == 'duplicates' ? i % 100 : i);
    }
    final distinct = shape == 'duplicates' ? 100 : count;
    final expected = [for (var i = 0; i < distinct; i++) i];
    bool ordered(Iterable<int> actual) {
      final iterator = actual.iterator;
      for (final value in expected) {
        if (!iterator.moveNext() || iterator.current != value) return false;
      }
      return !iterator.moveNext();
    }

    measure('extract_values/$shape', store.extractValues, ordered,
        operations: count);
    measure(
        'extract_map/$shape',
        store.extract,
        (map) =>
            map.length == count &&
            map.values.fold(0, (a, b) => a + b) ==
                (shape == 'duplicates'
                    ? count ~/ 100 * 4950
                    : count * (count - 1) ~/ 2),
        operations: count);
  }
  check(results.rows.isNotEmpty, 'No store operations matched $filter');
  results.save();
}
