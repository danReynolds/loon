import 'package:loon/loon.dart';
import '../iterable_draft.dart';
import '../profile_support.dart';
import '../visitor_draft.dart';

class Entry {
  final Document doc;
  final Set<Document> dependencies;
  Entry(this.doc, this.dependencies);
}

void profileIterable() {
  final results = ProfileResults();
  final methods = ['visitor', 'iterable', 'extract_values'];
  final order = profileSetting('PROFILE_ORDER') == 'reverse'
      ? methods.reversed.toList()
      : methods;
  const n = 100000;
  final store = ValueStore<int>();
  for (var i = 0; i < n; i++) {
    store.write('accounts__${i ~/ 1000}__items__${i % 1000}', i);
  }
  for (final (scope, path, expected) in [
    ('100k', 'accounts', n * (n - 1) ~/ 2),
    ('1k', 'accounts__42', (42000 + 42999) * 1000 ~/ 2),
  ]) {
    for (final method in order) {
      results.measure('sum/$scope/$method', () {
        var sum = 0;
        if (method == 'visitor') {
          visitValues(store, path, (value) => sum += value);
        } else {
          final values = method == 'iterable'
              ? valuesUnder(store, path)
              : store.extractValues(path);
          for (final value in values) {
            sum += value;
          }
        }
        return sum;
      }, expected: expected);
      results.measure('export/$scope/$method', () {
        final List<int> rows;
        if (method == 'visitor') {
          rows = [];
          visitValues(store, path, rows.add);
        } else {
          rows = (method == 'iterable'
                  ? valuesUnder(store, path)
                  : store.extractValues(path))
              .toList();
        }
        return rows.fold(0, (sum, value) => sum + value);
      }, expected: expected);
    }
  }

// Mirror DependencyManager cleanup with actual Document keys and stores.
// Setup and full correctness verification are outside the timed interval.
  final account = Document<int>('accounts', 'shared');
  final survivor = Document<int>('kept', 'survivor');
  final entries = [
    for (var i = 0; i < n; i++) Entry(Document<int>('deleted', '$i'), {account})
  ];
  for (final method in order) {
    final samples = <int>[];
    for (final recordSample in samplePhases()) {
      final forward = ValueStore<Entry>();
      final reverse = ValueStore<Set<Document>>();
      final dependents = <Document>{survivor};
      for (final entry in entries) {
        forward.write(entry.doc.path, entry);
        dependents.add(entry.doc);
      }
      reverse.write(account.path, dependents);
      forward.write(survivor.path, Entry(survivor, {account}));
      void remove(Entry entry) {
        for (final dependency in entry.dependencies) {
          final existing = reverse.get(dependency.path);
          if (existing == null) continue;
          existing.remove(entry.doc);
          if (existing.isEmpty) {
            reverse.delete(dependency.path, recursive: false);
          }
        }
      }

      final watch = Stopwatch()..start();
      if (method == 'visitor') {
        visitValues(forward, 'deleted', remove);
        forward.delete('deleted');
      } else if (method == 'iterable') {
        for (final entry in valuesUnder(forward, 'deleted')) {
          remove(entry);
        }
        forward.delete('deleted');
      } else {
        final extracted = forward.extractValues('deleted');
        forward.delete('deleted');
        for (final entry in extracted) {
          remove(entry);
        }
      }
      watch.stop();
      check(forward.extractValues().single.doc == survivor,
          'Surviving forward entry');
      check(
          reverse.get(account.path)!.length == 1 &&
              reverse.get(account.path)!.contains(survivor),
          'Surviving reverse entry');
      if (recordSample) samples.add(watch.elapsedMicroseconds);
    }
    results.add('cleanup/100k/$method', samples);
  }

// Mirror recursive getDependents: flatten sets with overlapping documents.
  final reverse = ValueStore<Set<Document>>();
  final docs = [for (var i = 0; i < n; i++) Document<int>('tx', '$i')];
  for (var i = 0; i < n ~/ 10; i++) {
    reverse.write('accounts__$i', {
      for (var j = 0; j < 20; j++) docs[(i * 10 + j) % n],
    });
  }
  for (final method in order) {
    results.measure('union/100k_10k_sets/$method', () {
      final combined = <Document>{};
      if (method == 'visitor') {
        visitValues(reverse, 'accounts', combined.addAll);
      } else {
        final groups = method == 'iterable'
            ? valuesUnder(reverse, 'accounts')
            : reverse.extractValues('accounts');
        for (final group in groups) {
          combined.addAll(group);
        }
      }
      return combined.length;
    }, expected: n);
  }
  results.save();
}
