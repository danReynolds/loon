import 'package:loon/loon.dart';
import '../extraction_draft.dart';
import '../iterable_draft.dart';
import '../profile_support.dart';
import '../visitor_draft.dart';

class IdentityEntry {
  final int id;
  IdentityEntry(this.id);
}

class EqualEntry {
  final int id;
  EqualEntry(this.id);
  @override
  int get hashCode => id.hashCode;
  @override
  bool operator ==(Object other) => other is EqualEntry && id == other.id;
}

void compareExtractionCost<T>(ProfileResults results, String name,
    List<T> input, String Function(int) pathFor, int Function(T) number) {
  final store = ValueStore<T>();
  for (var i = 0; i < input.length; i++) {
    store.write(pathFor(i), input[i]);
  }
  // Prebuilt controls are made before timing. The cached-set control does NOT
  // include maintaining an index; it only shows the potential read-side floor.
  final flat = <T>[];
  visitValues(store, '', flat.add);
  final expected = flat.toSet();
  final methods = <String, Set<T> Function()>{
    'current': () => store.extractValues(),
    'foreach_children': () => extractForEach(store, ''),
    'direct_loop': () => extractDirectLoop(store, ''),
    'unordered_hash_set': () => extractUnordered(store, ''),
    'lazy_to_set': () => valuesUnder(store, '').toSet(),
    'flat_list_to_set_control': () => flat.toSet(),
    'cached_set_copy_control': () => expected.toSet(),
  };
  final order = profileSetting('PROFILE_ORDER') == 'reverse'
      ? methods.keys.toList().reversed
      : methods.keys;
  for (final method in order) {
    final samples = <int>[];
    for (final record in samplePhases()) {
      final watch = Stopwatch()..start();
      final actual = methods[method]!();
      watch.stop();
      check(actual.length == expected.length && actual.containsAll(expected),
          '$name/$method membership');
      if (record) samples.add(watch.elapsedMicroseconds);
    }
    results.add('$name/extract/$method', samples,
        {'stored_values': input.length, 'distinct_values': expected.length});
  }
  final expectedSum = flat.fold(0, (sum, value) => sum + number(value));
  final expectedDistinctSum =
      expected.fold(0, (sum, value) => sum + number(value));
  final sums = <String, int Function()>{
    'callback': () {
      var sum = 0;
      visitValues(store, '', (value) => sum += number(value));
      return sum;
    },
    'lazy': () =>
        valuesUnder(store, '').fold(0, (sum, value) => sum + number(value)),
    'current_set': () =>
        store.extractValues().fold(0, (sum, value) => sum + number(value)),
    'foreach_set': () =>
        extractForEach(store, '').fold(0, (sum, value) => sum + number(value)),
    'flat_list_control': () =>
        flat.fold(0, (sum, value) => sum + number(value)),
  };
  final sumOrder = profileSetting('PROFILE_ORDER') == 'reverse'
      ? sums.keys.toList().reversed
      : sums.keys;
  for (final method in sumOrder) {
    results.measure('$name/sum/$method', sums[method]!,
        expected: method.endsWith('_set') ? expectedDistinctSum : expectedSum);
  }
}

void profileExtractionCost() {
  final results = ProfileResults();
  const n = 100000;
  String buckets(int i) => 'accounts__${i ~/ 1000}__items__${i % 1000}';
  compareExtractionCost(results, 'unique_ints_100k', List.generate(n, (i) => i),
      buckets, (value) => value);
  compareExtractionCost(
      results,
      'identity_entries_flat_100k',
      List.generate(n, IdentityEntry.new),
      (i) => 'transactions__$i',
      (value) => value.id);
  compareExtractionCost(results, 'repeated_ints_100k',
      List.generate(n, (i) => i % 100), buckets, (value) => value);
  compareExtractionCost(
      results,
      'equal_entries_100k',
      List.generate(n, (i) => EqualEntry(i % 100)),
      buckets,
      (value) => value.id);
  // Many small nodes make tree navigation significant instead of hiding it
  // behind 1000-value buckets. Paths include parent values and descendants.
  compareExtractionCost(
      results,
      'single_value_nodes_20k',
      List.generate(20000, (i) => i),
      (i) => 'accounts__${i}__item',
      (value) => value);
  compareExtractionCost(
      results,
      'deep_nodes_10k',
      List.generate(10000, (i) => i),
      (i) => 'accounts__${i}__a__b__c__d__e__item',
      (value) => value);
  results.save();
}
