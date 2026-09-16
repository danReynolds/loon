import 'package:loon/loon.dart';

import '../profile_support.dart';

/// Allocation-sensitive document operations. Outputs escape the timed function
/// and are checked afterwards, so construction cannot be optimized away.
void profileDocuments() {
  final results = ProfileResults();
  const n = 100000;
  final ids = [for (var i = 0; i < n; i++) '$i'];
  final flat = Loon.collection<int>('transactions');
  final nested =
      Loon.collection('users').doc('alice').subcollection<int>('transactions');
  final paths = [for (final id in ids) 'users__alice__transactions__$id'];
  final factories = <String, List<Document<int>> Function()>{
    'construct/flat_100k': () => [for (final id in ids) flat.doc(id)],
    'construct/nested_100k': () => [for (final id in ids) nested.doc(id)],
    'from_path/nested_100k': () =>
        [for (final path in paths) Document.fromPath<int>(path)],
  };
  final order = profileSetting('PROFILE_ORDER') == 'reverse'
      ? factories.keys.toList().reversed
      : factories.keys;
  for (final name in order) {
    final samples = <int>[];
    for (final record in samplePhases()) {
      final watch = Stopwatch()..start();
      final docs = factories[name]!();
      watch.stop();
      check(docs.length == n, 'Document count');
      final parent = name.contains('/flat_')
          ? 'transactions'
          : 'users__alice__transactions';
      for (var i = 0; i < n; i++) {
        check(
            docs[i].id == ids[i] &&
                docs[i].parent == parent &&
                docs[i].path == '${parent}__${ids[i]}',
            'Complete document identity');
      }
      if (record) samples.add(watch.elapsedMicroseconds);
    }
    results.add(name, samples, {'documents': n});
  }
  final expectedHash =
      ids.fold(0, (sum, id) => sum ^ Object.hash('transactions', id));
  List<Document<int>> docs = [];
  results.measure('hash/first_document_100k', () {
    var sum = 0;
    for (final doc in docs) {
      sum ^= doc.hashCode;
    }
    return sum;
  }, prepare: () {
    docs = [for (final id in ids) flat.doc(id)];
  }, expected: expectedHash);
  // Warm document identity before measuring uncached snapshot hashing.
  for (final doc in docs) {
    check(doc.hashCode >= 0, 'Hash initialized');
  }
  final snaps = [
    for (var i = 0; i < n; i++) DocumentSnapshot(doc: docs[i], data: i)
  ];
  final expectedSnaps =
      snaps.fold(0, (sum, snap) => sum ^ Object.hash(snap.doc, snap.data));
  results.measure('hash/snapshot_100k', () {
    var sum = 0;
    for (final snap in snaps) {
      sum ^= snap.hashCode;
    }
    return sum;
  }, expected: expectedSnaps);
  _profileRewire(results);
  results.save();
}

void _profileRewire(ProfileResults results) {
  const count = 1000;
  final sources = Loon.collection<int>('sources');
  final sourceDocs = [for (var i = 0; i < 33; i++) sources.doc('$i')];
  final first = sourceDocs.take(32).toSet();
  final second = {...sourceDocs.take(31), sourceDocs.last};
  final transactions = Loon.collection<int>('transactions',
      dependenciesBuilder: (snap) => snap.data == 0 ? first : second);
  final samples = <int>[];
  for (final record in samplePhases()) {
    Loon.configure(persistor: null);
    Loon.unsubscribe();
    Loon.clearAll(broadcast: false);
    final docs = [for (var i = 0; i < count; i++) transactions.doc('$i')];
    for (final doc in docs) {
      doc.create(0, broadcast: false, persist: false);
    }
    final watch = Stopwatch()..start();
    for (final doc in docs) {
      doc.update(1, broadcast: false, persist: false);
    }
    watch.stop();
    check(sourceDocs[31].dependents() == null, 'Departed source pruned');
    check(
        sourceDocs[32].dependents()!.length == count, 'New source membership');
    for (final source in sourceDocs.take(31)) {
      check(source.dependents()!.length == count, 'Shared source membership');
    }
    for (final doc in docs) {
      check(doc.dependencies()!.containsAll(second), 'Forward membership');
    }
    Loon.clearAll(broadcast: false);
    if (record) samples.add(watch.elapsedMicroseconds);
  }
  results.add('rewire/1k_docs_32_dependencies_one_changed', samples,
      {'documents': count, 'dependencies_per_document': 32});
}
