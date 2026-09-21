import 'package:fake_async/fake_async.dart';
import 'package:loon/loon.dart';
import '../profile_support.dart';
import 'dependency.dart' show flush;

// Complements the same-collection workloads with poor locality and graph reuse.
void profileDependencyShapes() {
  final results = ProfileResults();
  for (final shape in ['scattered', 'shared_cycle', 'alternating_deletions']) {
    const count = 20000;
    final samples = <String, List<int>>{
      'propagate': [],
      'delete': [],
    };
    for (final record in samplePhases()) {
      fakeAsync((async) {
        Loon.configure(persistor: null);
        Loon.unsubscribe();
        Loon.clearAll(broadcast: false);
        final accounts = Loon.collection<int>('accounts');
        final source = accounts.doc('source');
        final other = accounts.doc('other');
        source.create(0, broadcast: false, persist: false);
        other.create(0, broadcast: false, persist: false);
        final root = Loon.collection('groups');
        final summaries = Loon.collection<int>('summaries');
        final docs = <Document<int>>[];
        for (var i = 0; i < count; i++) {
          final collection = root
              .doc('${shape == 'scattered' ? i % 5000 : 0}')
              .subcollection<int>('items',
                  dependenciesBuilder: (_) => {
                        if (shape != 'alternating_deletions' || i.isEven)
                          source,
                        if (shape == 'alternating_deletions' && i.isOdd) other,
                      });
          final doc = collection.doc('$i');
          doc.create(i, broadcast: false, persist: false);
          docs.add(doc);
        }
        if (shape == 'shared_cycle') {
          final summary = Loon.collection<int>('summaries',
              dependenciesBuilder: (_) => docs.toSet()).doc('all');
          summary.create(0, broadcast: false, persist: false);
          // Complete the cycle: source -> items -> summary -> source.
          final cyclicSource = Loon.collection<int>('accounts',
              dependenciesBuilder: (_) => {summary}).doc('source');
          cyclicSource.update(0, broadcast: false, persist: false);
        }
        flush(async);
        final watch = Stopwatch()..start();
        source.update(1, persist: false);
        watch.stop();
        final propagate = watch.elapsedMicroseconds;
        final events = ValueStore<BroadcastEvents>(
            Loon.inspect()['broadcastStore']['events']);
        var touched = 0;
        for (final doc in docs) {
          if (events.get(doc.path) == BroadcastEvents.touched) touched++;
        }
        check(
            touched == (shape == 'alternating_deletions' ? count ~/ 2 : count),
            'Reached dependents in $shape');
        check(events.get(source.path) == BroadcastEvents.modified,
            'Cycle preserves source event');
        if (shape == 'shared_cycle') {
          check(
              events.get(summaries.doc('all').path) == BroadcastEvents.touched,
              'Shared summary reached');
        }
        flush(async);
        watch.reset();
        watch.start();
        root.delete();
        watch.stop();
        final deletion = watch.elapsedMicroseconds;
        final reverse =
            ValueStore<Set<Document>>(Loon.inspect()['dependentsStore']);
        check(
            reverse.get(source.path) == null && reverse.get(other.path) == null,
            'Deleted entries detached from sources');
        flush(async);
        Loon.unsubscribe();
        Loon.clearAll(broadcast: false);
        if (record) {
          samples['propagate']!.add(propagate);
          samples['delete']!.add(deletion);
        }
      });
    }
    samples.forEach((name, values) => results.add('$shape/$name', values, {
          'documents': count,
          'collections': shape == 'scattered' ? 5000 : 1,
        }));
  }
  results.save();
}
