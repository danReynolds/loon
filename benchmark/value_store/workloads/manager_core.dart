// Standalone algorithm isolation only; run_core.dart supplies the actual
// managers and stores alongside explicit fixture document handles.
const managerWorkload = r'''
import 'package:loon/loon.dart';
import '../profile_support.dart';

void profileManagerCore() {
  final results = ProfileResults();
  final filter = profileSetting('PROFILE_FILTER');
  final selected = filter == null ? null : RegExp(filter);
  const n = 20000;
  const updates = 200;
  final manager = Loon.dependencies;

  void measure(String name, void Function() action, bool Function() validate,
      {required void Function() prepare, required int operations}) {
    if (selected != null && !selected.hasMatch(name)) return;
    final samples = <int>[];
    for (final record in samplePhases()) {
      prepare();
      final watch = Stopwatch()..start();
      action();
      watch.stop();
      check(validate(), 'manager_core/$name');
      if (record) samples.add(watch.elapsedMicroseconds);
    }
    results.add(name, samples, {'operations': operations});
  }

  final sources = [for (var i = 0; i < 9; i++) Document<int>('accounts', '$i')];
  for (final width in [1, 8]) {
    final initial = sources.take(width).toSet();
    final replacement = sources.skip(1).take(width).toSet();
    final docs = [
      for (var i = 0; i < n; i++)
        Document<Set<Document>?>('orgs__o__items', '$i',
            dependenciesBuilder: (snap) => snap.data)
    ];
    final seeded = [
      for (final doc in docs) DocumentSnapshot(doc: doc, data: initial)
    ];
    void seed() {
      manager.clear();
      for (final snap in seeded) {
        manager.updateDependencies(snap);
      }
    }

    measure('dependencies/initial_$width', () {
      for (final snap in seeded) {
        manager.updateDependencies(snap);
      }
    }, () => manager.getDependents(sources.first)!.length == n,
        prepare: manager.clear, operations: n);

    for (final (kind, deps) in [
      ('unchanged', initial),
      ('replace_one', replacement),
      ('clear_null', null),
      ('clear_empty', <Document>{}),
    ]) {
      final changed = [
        for (final doc in docs.take(updates))
          DocumentSnapshot<Set<Document>?>(doc: doc, data: deps)
      ];
      measure('dependencies/${kind}_$width', () {
        for (final snap in changed) {
          manager.updateDependencies(snap);
        }
      }, () {
        final expected = deps == null || deps.isEmpty ? null : deps;
        return changed.every((snap) =>
                setEquals(manager.getDependencies(snap.doc), expected)) &&
            manager.getDependents(sources.first)!.length ==
                (kind == 'unchanged' ? n : n - updates);
      }, prepare: seed, operations: updates);
    }
  }

  // Deleting a collection unlinks each deleted document from its dependencies' reverse indexes.
  final deletedSources = [
    for (var i = 0; i < n; i++) Document<int>('sources', '$i')
  ];
  for (final shared in [true, false]) {
    final records = [
      for (var i = 0; i < n; i++)
        Document<int>('records', '$i',
            dependenciesBuilder: (_) => {deletedSources[shared ? 0 : i]})
    ];
    measure('dependencies/delete_${shared ? 'shared' : 'spread'}', () {
      manager.deleteCollection(Collection('records'));
    }, () {
      return manager.getDependents(deletedSources.first) == null &&
          manager.getDependents(deletedSources.last) == null &&
          manager.getDependencies(records.last) == null;
    }, prepare: () {
      manager.clear();
      for (final doc in records) {
        manager.updateDependencies(DocumentSnapshot(doc: doc, data: 0));
      }
    }, operations: n);
  }

  final broadcasts = BroadcastManager();
  for (final collections in [1, 5000]) {
    final source = Document<int>('accounts', 'source');
    final docs = [
      for (var i = 0; i < n; i++)
        Document<int>('orgs__o__groups__${i % collections}__items', '$i',
            dependenciesBuilder: (_) => {source})
    ];
    manager.clear();
    for (final doc in docs) {
      manager.updateDependencies(DocumentSnapshot(doc: doc, data: 0));
    }
    // Close a diamond and a cycle, exercising the pending-event visited guard.
    manager.updateDependencies(DocumentSnapshot(
        doc: Document<int>(source.parent, source.id,
            dependenciesBuilder: (_) => {docs.first, docs.last}),
        data: 0));
    for (final populated in [false, true]) {
      measure('propagation/${collections}_${populated ? 'warm' : 'empty'}', () {
        broadcasts.writeDocument(source, BroadcastEvents.modified);
      }, () {
        return broadcasts.eventStore.get(source.path) == BroadcastEvents.modified &&
            docs.every((doc) => broadcasts.eventStore.get(doc.path) == BroadcastEvents.touched) &&
            broadcasts.observerValueStore.isEmpty;
      }, prepare: () {
        broadcasts.clear(broadcast: false);
        for (final doc in docs) {
          broadcasts.observerValueStore.write(doc.path, 1);
          broadcasts.observerValueStore.write(doc.parent, 1);
          if (populated) {
            // Existing siblings keep maps available without marking dependents visited.
            broadcasts.eventStore.write('${doc.parent}__existing', BroadcastEvents.added);
          }
        }
      }, operations: n);
    }
  }
  manager.clear();
  final plain = [for (var i = 0; i < n; i++) Document<int>('plain', '$i')];
  measure('writes/plain', () {
    for (final doc in plain) {
      broadcasts.writeDocument(doc, BroadcastEvents.added);
    }
  }, () {
    return plain.every(
        (doc) => broadcasts.eventStore.get(doc.path) == BroadcastEvents.added);
  }, prepare: () {
    broadcasts.clear(broadcast: false);
  }, operations: n);

  // Each source has one dependent in each further collection, so writing the sources
  // alternates between `depth` collections in the event store and the reverse index.
  for (final (depth, prefix) in [
    (2, ''),
    (3, ''),
    (2, 'orgs__o__groups__g__'),
    (3, 'orgs__o__groups__g__'),
  ]) {
    manager.clear();
    final sources = [
      for (var i = 0; i < n ~/ depth; i++) Document<int>('${prefix}level0', '$i')
    ];
    final all = <Document<int>>[...sources];
    var previous = sources;
    for (var d = 1; d < depth; d++) {
      final parents = previous;
      final level = [
        for (var i = 0; i < parents.length; i++)
          Document<int>('${prefix}level$d', '$i',
              dependenciesBuilder: (_) => {parents[i]})
      ];
      for (final doc in level) {
        manager.updateDependencies(DocumentSnapshot(doc: doc, data: 0));
      }
      all.addAll(level);
      previous = level;
    }
    final shape = prefix.isEmpty ? 'shallow' : 'deep';
    measure('propagation/chains_${shape}_$depth', () {
      for (final source in sources) {
        broadcasts.writeDocument(source, BroadcastEvents.modified);
      }
    }, () {
      return all.every((doc) => broadcasts.eventStore.get(doc.path) != null);
    }, prepare: () {
      broadcasts.clear(broadcast: false);
    }, operations: all.length);
  }
  broadcasts.clear(broadcast: false);
  check(results.rows.isNotEmpty, 'No manager_core operations matched $filter');
  results.save();
}
''';
