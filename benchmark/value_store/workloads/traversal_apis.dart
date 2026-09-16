import 'package:loon/loon.dart';
import '../iterable_draft.dart';
import '../profile_support.dart';
import '../traversal_api_draft.dart';
import '../value_batches_draft.dart';
import '../visitor_draft.dart';

enum TraversalApi {
  callback,
  typedCallback,
  generator,
  iterator,
  buckets,
  specialized,
  extraction,
}

Iterable<TraversalApi> apiOrder() =>
    profileSetting('PROFILE_ORDER') == 'reverse'
        ? TraversalApi.values.reversed
        : TraversalApi.values;

// Separate consumers keep the ordinary loops' accumulators out of the callback
// closure's lexical scope. Sharing one captured accumulator would bias them.
int sumWithApi(TraversalApi api, ValueStore<int> store, String path) =>
    switch (api) {
      TraversalApi.callback => _sumCallback(store, path, false),
      TraversalApi.typedCallback => _sumCallback(store, path, true),
      TraversalApi.generator => _sumGenerator(store, path),
      TraversalApi.iterator => _sumIterator(store, path),
      TraversalApi.buckets => _sumBuckets(store, path),
      TraversalApi.specialized => sumSpecialized(store, path),
      TraversalApi.extraction => _sumExtracted(store, path),
    };

int _sumCallback(ValueStore<int> store, String path, bool typed) {
  var sum = 0;
  if (typed) {
    visitTypedValues(store, path, (value) => sum += value);
  } else {
    visitValues(store, path, (value) => sum += value);
  }
  return sum;
}

int _sumGenerator(ValueStore<int> store, String path) {
  var sum = 0;
  for (final value in valuesUnder(store, path)) {
    sum += value;
  }
  return sum;
}

int _sumIterator(ValueStore<int> store, String path) {
  var sum = 0;
  for (final value in manualValuesUnder(store, path)) {
    sum += value;
  }
  return sum;
}

int _sumBuckets(ValueStore<int> store, String path) {
  var sum = 0;
  for (final bucket in valueBatches(store, path)) {
    for (final value in bucket) {
      sum += value;
    }
  }
  return sum;
}

int _sumExtracted(ValueStore<int> store, String path) {
  var sum = 0;
  for (final value in store.extractValues(path)) {
    sum += value;
  }
  return sum;
}

List<T> exportWithApi<T>(TraversalApi api, ValueStore<T> store, String path) {
  final result = <T>[];
  switch (api) {
    case TraversalApi.callback:
      visitValues(store, path, result.add);
    case TraversalApi.typedCallback:
      visitTypedValues(store, path, result.add);
    case TraversalApi.generator:
      return valuesUnder(store, path).toList();
    case TraversalApi.iterator:
      return manualValuesUnder(store, path).toList();
    case TraversalApi.buckets:
      for (final bucket in valueBatches(store, path)) {
        result.addAll(bucket);
      }
    case TraversalApi.specialized:
      return exportSpecialized(store, path);
    case TraversalApi.extraction:
      return store.extractValues(path).toList();
  }
  return result;
}

void cleanupWithApi(TraversalApi api, ValueStore<TraversalEntry> forward,
    String path, ValueStore<Set<Document>> reverse) {
  switch (api) {
    case TraversalApi.callback:
      _cleanupCallback(forward, path, reverse, false);
    case TraversalApi.typedCallback:
      _cleanupCallback(forward, path, reverse, true);
    case TraversalApi.generator:
      for (final entry in valuesUnder(forward, path)) {
        removeTraversalEntry(entry, reverse);
      }
    case TraversalApi.iterator:
      for (final entry in manualValuesUnder(forward, path)) {
        removeTraversalEntry(entry, reverse);
      }
    case TraversalApi.buckets:
      for (final bucket in valueBatches(forward, path)) {
        for (final entry in bucket) {
          removeTraversalEntry(entry, reverse);
        }
      }
    case TraversalApi.specialized:
      cleanupSpecialized(forward, path, reverse);
    case TraversalApi.extraction:
      final entries = forward.extractValues(path);
      forward.delete(path);
      for (final entry in entries) {
        removeTraversalEntry(entry, reverse);
      }
      return;
  }
  // Only the separate reverse index changes while the forward index is walked.
  forward.delete(path);
}

void _cleanupCallback(ValueStore<TraversalEntry> forward, String path,
    ValueStore<Set<Document>> reverse, bool typed) {
  if (typed) {
    visitTypedValues(
        forward, path, (entry) => removeTraversalEntry(entry, reverse));
  } else {
    visitValues(forward, path, (entry) => removeTraversalEntry(entry, reverse));
  }
}

Set<Document> unionWithApi(
    TraversalApi api, ValueStore<Set<Document>> store, String path) {
  final result = <Document>{};
  switch (api) {
    case TraversalApi.callback:
      visitValues(store, path, result.addAll);
    case TraversalApi.typedCallback:
      visitTypedValues(store, path, result.addAll);
    case TraversalApi.generator:
      for (final group in valuesUnder(store, path)) {
        result.addAll(group);
      }
    case TraversalApi.iterator:
      for (final group in manualValuesUnder(store, path)) {
        result.addAll(group);
      }
    case TraversalApi.buckets:
      for (final bucket in valueBatches(store, path)) {
        for (final group in bucket) {
          result.addAll(group);
        }
      }
    case TraversalApi.specialized:
      return unionSpecialized(store, path);
    case TraversalApi.extraction:
      for (final group in store.extractValues(path)) {
        result.addAll(group);
      }
  }
  return result;
}

void _measureChecked<T>(ProfileResults results, String name,
    T Function() action, void Function(T) verify) {
  final samples = <int>[];
  for (final record in samplePhases()) {
    final watch = Stopwatch()..start();
    final result = action();
    watch.stop();
    verify(result);
    if (record) samples.add(watch.elapsedMicroseconds);
  }
  results.add(name, samples);
}

void _profileSumAndExport(ProfileResults results) {
  for (final shape in [
    'buckets_100k',
    'flat_100k',
    'singletons_20k',
    'deep_10k'
  ]) {
    final n = shape == 'singletons_20k'
        ? 20000
        : shape == 'deep_10k'
            ? 10000
            : 100000;
    final store = ValueStore<int>();
    for (var i = 0; i < n; i++) {
      final path = switch (shape) {
        'flat_100k' => 'accounts__$i',
        'singletons_20k' => 'accounts__${i}__value',
        'deep_10k' => 'accounts__${i}__a__b__c__d__e__value',
        _ => 'accounts__${i ~/ 1000}__items__${i % 1000}',
      };
      store.write(path, i);
    }
    final expected = List.generate(n, (i) => i);
    for (final api in apiOrder()) {
      results.measure(
          'sum/$shape/${api.name}', () => sumWithApi(api, store, 'accounts'),
          expected: n * (n - 1) ~/ 2);
      _measureChecked(results, 'export/$shape/${api.name}',
          () => exportWithApi(api, store, 'accounts'), (actual) {
        check(actual.length == expected.length, 'Export length');
        for (var i = 0; i < actual.length; i++) {
          check(actual[i] == expected[i], 'Export order/value at $i');
        }
      });
    }
    if (shape == 'buckets_100k') {
      for (final api in apiOrder()) {
        // Repeat the smaller subtree operation to stay above timer resolution.
        results.measure('sum/scoped_1k_x100/${api.name}', () {
          var total = 0;
          for (var repeat = 0; repeat < 100; repeat++) {
            total += sumWithApi(api, store, 'accounts__42');
          }
          return total;
        }, expected: (42000 + 42999) * 1000 ~/ 2 * 100, operations: 100);
      }
    }
  }
}

void _profileCleanup(ProfileResults results) {
  for (final nested in [false, true]) {
    final n = nested ? 10000 : 100000;
    final path = nested ? 'accounts__gone' : 'transactions';
    final sources = [
      for (var i = 0; i < (nested ? 100 : 1); i++)
        Document<int>('sources', '$i')
    ];
    final survivor = Document<int>('kept', 'survivor');
    final entries = [
      for (var i = 0; i < n; i++)
        TraversalEntry(
          nested && i == 0
              ? Document<int>('accounts', 'gone')
              : Document<int>(
                  nested
                      ? 'accounts__gone__groups__${i ~/ 100}__transactions'
                      : path,
                  '$i'),
          {
            sources[i % sources.length],
            if (nested) sources[(i + 1) % sources.length]
          },
        )
    ];
    for (final api in apiOrder()) {
      final samples = <int>[];
      for (final record in samplePhases()) {
        final forward = ValueStore<TraversalEntry>();
        final reverse = ValueStore<Set<Document>>();
        for (final source in sources) {
          reverse.write(source.path, <Document>{});
        }
        for (final entry in entries) {
          forward.write(entry.doc.path, entry);
          for (final source in entry.dependencies) {
            reverse.get(source.path)!.add(entry.doc);
          }
        }
        forward.write(survivor.path, TraversalEntry(survivor, {sources.first}));
        reverse.get(sources.first.path)!.add(survivor);
        final watch = Stopwatch()..start();
        cleanupWithApi(api, forward, path, reverse);
        watch.stop();
        final remainingForward = forward.extract();
        check(
            remainingForward.length == 1 &&
                remainingForward[survivor.path]?.doc == survivor,
            'Surviving forward entry');
        final remainingReverse = reverse.extract();
        check(
            remainingReverse.length == 1 &&
                remainingReverse[sources.first.path]!.length == 1 &&
                remainingReverse[sources.first.path]!.contains(survivor),
            'Complete reverse cleanup');
        if (record) samples.add(watch.elapsedMicroseconds);
      }
      results.add(
          'cleanup/${nested ? 'nested_10k_two_dependencies' : 'flat_100k'}/${api.name}',
          samples);
    }
  }
}

void _profileUnion(ProfileResults results) {
  const n = 100000;
  final store = ValueStore<Set<Document>>();
  final docs = [for (var i = 0; i < n; i++) Document<int>('tx', '$i')];
  for (var i = 0; i < n ~/ 10; i++) {
    store.write(
        'accounts__$i', {for (var j = 0; j < 20; j++) docs[(i * 10 + j) % n]});
  }
  final expected = docs.toSet();
  for (final api in apiOrder()) {
    _measureChecked(results, 'union/100k_10k_sets/${api.name}',
        () => unionWithApi(api, store, 'accounts'), (actual) {
      check(actual.length == expected.length && actual.containsAll(expected),
          'Complete union membership');
    });
  }
}

// A small control for the syntax question. These are concrete SDK collections;
// rankings here do not establish a rule for arbitrary Iterable implementations.
void _profileLoopStyles(ProfileResults results) {
  const n = 100000;
  final values = List.generate(n, (i) => i);
  final map = {for (var i = 0; i < n; i++) '$i': i};
  final actions = <String, int Function()>{
    'list_for_in': () {
      var sum = 0;
      for (final value in values) {
        sum += value;
      }
      return sum;
    },
    'list_for_each': () {
      var sum = 0;
      // Deliberate comparison against for-in in this benchmark.
      // ignore: avoid_function_literals_in_foreach_calls
      values.forEach((value) => sum += value);
      return sum;
    },
    'map_keys_lookup': () {
      var sum = 0;
      for (final key in map.keys) {
        sum += map[key]!;
      }
      return sum;
    },
    'map_entries': () {
      var sum = 0;
      for (final entry in map.entries) {
        sum += entry.value;
      }
      return sum;
    },
    'map_values': () {
      var sum = 0;
      for (final value in map.values) {
        sum += value;
      }
      return sum;
    },
    'map_for_each': () {
      var sum = 0;
      map.forEach((key, value) => sum += value);
      return sum;
    },
  };
  final order = profileSetting('PROFILE_ORDER') == 'reverse'
      ? actions.keys.toList().reversed
      : actions.keys;
  for (final name in order) {
    results.measure('loop_style/$name', actions[name]!,
        expected: n * (n - 1) ~/ 2);
  }
}

void profileTraversalApis() {
  final results = ProfileResults();
  _profileSumAndExport(results);
  _profileCleanup(results);
  _profileUnion(results);
  _profileLoopStyles(results);
  results.save();
}
