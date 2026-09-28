import 'package:fake_async/fake_async.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:loon/loon.dart';

import '../utils.dart';

void main() {
  setUp(() => Loon.configure(persistor: null));
  tearDown(() async {
    Loon.unsubscribe();
    await Loon.clearAll(broadcast: false);
  });

  for (final transitive in [false, true]) {
    test(
        'invalidates a re-cached query on repeated ${transitive ? "transitive" : "direct"} dependency writes',
        () {
      fakeAsync((async) {
        final source = Loon.collection<bool>('sources').doc('one');
        source.create(true, broadcast: false);
        final intermediate = Loon.collection<int>('intermediate',
            dependenciesBuilder: (_) => {source}).doc('one');
        intermediate.create(0, broadcast: false);
        final items = Loon.collection<int>('items',
            dependenciesBuilder: (_) => {transitive ? intermediate : source});
        items.doc('one').create(1, broadcast: false);
        final query = items.where((_) => source.get()!.data);
        final observed = query.observe();
        final emissions = <List<String>>[];
        observed.stream().listen(
            (snaps) => emissions.add(snaps.map((snap) => snap.id).toList()));
        flushBroadcasts(async);

        source.update(false);
        expect(observed.get(), isEmpty);
        source.update(true);
        flushBroadcasts(async);

        expect(observed.get(), query.get());
        expect(emissions, [
          ['one'],
          ['one']
        ]);
      });
    });
  }

  test('invalidates a re-cached query through a dependency cycle', () {
    fakeAsync((async) {
      final a = Loon.collection<int>('a',
          dependenciesBuilder: (_) =>
              {Loon.collection<int>('b').doc('one')}).doc('one');
      final b =
          Loon.collection<int>('b', dependenciesBuilder: (_) => {a}).doc('one');
      final items =
          Loon.collection<int>('items', dependenciesBuilder: (_) => {b});
      a.create(1, broadcast: false);
      b.create(1, broadcast: false);
      items.doc('one').create(1, broadcast: false);
      final query = items.where((_) => a.get()!.data > 1);
      final observed = query.observe();
      final emissions = <List<String>>[];
      observed.stream().listen(
          (snaps) => emissions.add(snaps.map((snap) => snap.id).toList()));
      flushBroadcasts(async);

      a.update(2);
      expect(observed.get(), hasLength(1));
      a.update(0);
      expect(observed.get(), isEmpty);
      a.update(3);
      flushBroadcasts(async);

      expect(observed.get(), query.get());
      expect(emissions, [
        [],
        ['one']
      ]);
    });
  });

  test('a dependency touch preserves a pending modified event', () {
    fakeAsync((async) {
      final source = Loon.collection<int>('sources').doc('one');
      source.create(1, broadcast: false);
      final child =
          Loon.collection<int>('items', dependenciesBuilder: (_) => {source})
              .doc('one');
      child.create(1, broadcast: false);
      final events = <BroadcastEvents>[];
      child
          .observe()
          .streamChanges()
          .listen((change) => events.add(change.event));

      child.update(2);
      source.update(2);
      flushBroadcasts(async);

      expect(events, [BroadcastEvents.modified]);
    });
  });
}
