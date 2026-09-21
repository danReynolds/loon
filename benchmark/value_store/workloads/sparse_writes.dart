import 'package:fake_async/fake_async.dart';
import 'package:loon/loon.dart';
import '../profile_support.dart';
import 'dependency.dart' show flush;

/// Large resident collection, sparse updates, little work per propagation.
void profileSparseWrites() {
  final results = ProfileResults();
  const count = 50000;
  const updates = 1000;
  for (final withDependents in [false, true]) {
    final samples = <int>[];
    for (final record in samplePhases()) {
      fakeAsync((async) {
        Loon.configure(persistor: null);
        Loon.unsubscribe();
        Loon.clearAll(broadcast: false);
        final sources = Loon.collection<int>('sources');
        final leaves = Loon.collection<int>('leaves',
            dependenciesBuilder: (snap) => {sources.doc('${snap.data}')});
        for (var i = 0; i < count; i++) {
          sources.doc('$i').create(0, broadcast: false, persist: false);
          if (withDependents) {
            leaves.doc('$i').create(i, broadcast: false, persist: false);
          }
        }
        final changed = [
          for (var i = 0; i < updates; i++) sources.doc('${i * 47 % count}')
        ];
        final watch = Stopwatch()..start();
        for (final doc in changed) {
          doc.update(1, persist: false);
        }
        watch.stop();
        final events = ValueStore<BroadcastEvents>(
            Loon.inspect()['broadcastStore']['events']);
        check(events.getChildValues('sources')?.length == updates,
            'Source events queued');
        check(
            (events.getChildValues('leaves')?.length ?? 0) ==
                (withDependents ? updates : 0),
            'Dependent events queued');
        watch.start();
        flush(async);
        watch.stop();
        check(pendingEventCount() == 0, 'Broadcast drained');
        for (final doc in changed) {
          check(doc.get()!.data == 1, 'Sparse update data');
        }
        Loon.unsubscribe();
        Loon.clearAll(broadcast: false);
        if (record) samples.add(watch.elapsedMicroseconds);
      });
    }
    results.add(withDependents ? 'one_dependent' : 'no_dependents', samples, {
      'documents': count * (withDependents ? 2 : 1),
      'updates': updates,
    });
  }
  results.save();
}

int pendingEventCount() =>
    ValueStore<BroadcastEvents>(Loon.inspect()['broadcastStore']['events'])
        .extract()
        .length;
