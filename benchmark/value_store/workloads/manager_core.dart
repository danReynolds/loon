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
  broadcasts.clear(broadcast: false);
  check(results.rows.isNotEmpty, 'No manager_core operations matched $filter');
  results.save();
}
''';
