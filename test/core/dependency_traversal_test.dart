import 'package:fake_async/fake_async.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:loon/loon.dart';

ValueStore<BroadcastEvents> pendingEvents() =>
    ValueStore(Loon.inspect()['broadcastStore']['events']);

void main() {
  setUp(() {
    Loon.configure(persistor: null);
    Loon.unsubscribe();
    Loon.clearAll(broadcast: false);
  });
  tearDown(() async {
    Loon.unsubscribe();
    await Loon.clearAll(broadcast: false);
  });

  test('Dependency updates store only non-empty results and keep child entries',
      () {
    final source = Document<int>('sources', 'one');
    Set<Document>? selected;
    final doc =
        Document<int>('items', 'one', dependenciesBuilder: (_) => selected);
    doc.create(0, broadcast: false, persist: false);
    expect(doc.dependencies(), isNull);

    final child = doc
        .subcollection<int>('children', dependenciesBuilder: (_) => {source})
        .doc('one');
    child.create(0, broadcast: false, persist: false);
    for (final (deps, expected, ownsEdge) in [
      (<Document>{}, null, false),
      (<Document>{}, null, false),
      ({source}, {source}, true),
      (<Document>{}, null, false),
      ({source}, {source}, true),
      (null, null, false),
    ]) {
      selected = deps;
      doc.rebuildDependencies();
      expect(doc.dependencies(), expected);
      expect(child.dependencies(), {source});
      expect(source.dependents(), {
        child,
        if (ownsEdge) doc,
      });
    }
  });

  test('Propagation handles unusual segment boundaries, diamonds and cycles',
      () {
    fakeAsync((async) {
      final sink = Document<int>('summaries', 'sink');
      final source = Document<int>('accounts', 'source',
          dependenciesBuilder: (_) => {sink});
      source.create(0, broadcast: false, persist: false);
      final docs = [
        for (final (parent, id) in [
          ('items', 'a'),
          ('odd_', 'b'),
          ('items', 'nested__c'),
          ('empty_id', ''),
          ('', 'leading'),
          ('items', 'z'),
        ])
          Document<int>(parent, id, dependenciesBuilder: (_) => {source})
      ];
      for (final doc in docs) {
        doc.create(0, broadcast: false, persist: false);
      }
      Document<int>(sink.parent, sink.id,
              dependenciesBuilder: (_) => {docs.first, docs.last})
          .create(0, broadcast: false, persist: false);
      source.update(1, persist: false);
      expect(pendingEvents().get(source.path), BroadcastEvents.modified);
      for (final doc in [...docs, sink]) {
        expect(pendingEvents().get(doc.path), BroadcastEvents.touched,
            reason: doc.path);
      }
      async.elapse(const Duration(milliseconds: 1));
      expect(pendingEvents().extract(), isEmpty);

      // A second operation must resolve fresh buckets after event-store clear.
      source.update(2, persist: false);
      for (final doc in [...docs, sink]) {
        expect(pendingEvents().get(doc.path), BroadcastEvents.touched,
            reason: doc.path);
      }
      async.elapse(const Duration(milliseconds: 1));
    });
  });

  test('Shared-dependency deletion preserves survivors and permits recreation',
      () {
    fakeAsync((async) {
      final source = Loon.collection<int>('accounts').doc('source');
      source.create(0, broadcast: false, persist: false);
      final deleted =
          Loon.collection<int>('deleted', dependenciesBuilder: (_) => {source});
      final surviving = Loon.collection<int>('surviving',
          dependenciesBuilder: (_) => {source}).doc('one');
      for (var i = 0; i < 100; i++) {
        deleted.doc('$i').create(i, broadcast: false, persist: false);
      }
      surviving.create(0, broadcast: false, persist: false);
      deleted.delete();
      async.elapse(const Duration(milliseconds: 1));
      source.update(1, persist: false);
      expect(pendingEvents().get(surviving.path), BroadcastEvents.touched);
      expect(pendingEvents().extract('deleted'), isEmpty);
      async.elapse(const Duration(milliseconds: 1));
      surviving.delete();
      deleted.doc('new').create(0, broadcast: false, persist: false);
      async.elapse(const Duration(milliseconds: 1));
      source.update(2, persist: false);
      expect(pendingEvents().get(deleted.doc('new').path),
          BroadcastEvents.touched);
      expect(pendingEvents().get(surviving.path), isNull);
      async.elapse(const Duration(milliseconds: 1));
    });
  });
}
