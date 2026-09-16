import 'package:loon/loon.dart';
import '../iterable_draft.dart';
import '../profile_support.dart';
import '../value_batches_draft.dart';

class Entry {
  final int id;
  Entry(this.id);
}

void compare<T>(ProfileResults results, String name, List<T> values) {
  final store = ValueStore<T>();
  for (var i = 0; i < values.length; i++) {
    store.write('accounts__${i ~/ 1000}__items__${i % 1000}', values[i]);
  }
  final methods = [
    'extract_values',
    'iterable_to_set',
    'batch_extraction',
    'batch_iterable_to_set',
  ];
  final order =
      profileSetting('PROFILE_ORDER') == 'reverse' ? methods.reversed : methods;
  for (final (scope, path, expected) in [
    ('root', '', values.toSet()),
    ('account', 'accounts__42', values.sublist(42000, 43000).toSet()),
  ]) {
    for (final method in order) {
      final samples = <int>[];
      for (final recordSample in samplePhases()) {
        final watch = Stopwatch()..start();
        final actual = switch (method) {
          'extract_values' => store.extractValues(path),
          'iterable_to_set' => valuesUnder(store, path).toSet(),
          'batch_extraction' => extractViaBatches(store, path),
          _ => valuesViaBatches(store, path).toSet(),
        };
        watch.stop();
        // Compare membership outside timing, not merely result cardinality.
        check(actual.length == expected.length, 'Extracted set length');
        check(actual.containsAll(expected), 'Extracted set membership');
        if (recordSample) samples.add(watch.elapsedMicroseconds);
      }
      results.add('$name/$scope/$method', samples);
    }
  }
}

void profileExtraction() {
  final results = ProfileResults();
  const n = 100000;
  compare(results, 'unique_ints', [for (var i = 0; i < n; i++) i]);
  compare(results, 'identity_entries', [for (var i = 0; i < n; i++) Entry(i)]);
  compare(
      results, 'repeated_100_values', [for (var i = 0; i < n; i++) i % 100]);
  results.save();
}
