import 'package:fake_async/fake_async.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:loon/loon.dart';

import '../utils.dart';

/// A disposed observer releases its controllers and last value, its streams are empty, and
/// observing it again returns a fresh observer.

void _reset(FakeAsync async) {
  Loon.unsubscribe();
  Loon.clearAll(broadcast: false);
  async.flushMicrotasks();
}

void main() {
  tearDown(() async {
    Loon.unsubscribe();
    await Loon.clearAll();
  });

  test('A disposed observer stops delivering and exposes empty streams', () {
    fakeAsync((async) {
      _reset(async);
      final doc = Loon.collection<int>('items').doc('1');
      doc.create(1);
      flushBroadcasts(async);

      final obs = doc.observe();
      final events = <int?>[];
      final sub = obs.stream().listen((snap) => events.add(snap?.data));
      flushBroadcasts(async);

      obs.dispose();
      doc.update(2);
      flushBroadcasts(async);

      final afterDispose = <int?>[];
      final changesAfterDispose = <BroadcastEvents>[];
      final sub2 = obs.stream().listen((snap) => afterDispose.add(snap?.data));
      final sub3 = obs.streamChanges().listen((change) => changesAfterDispose.add(change.event));
      flushBroadcasts(async);

      expect(events, [1]);
      expect(afterDispose, isEmpty);
      expect(changesAfterDispose, isEmpty);
      // Disposing again is a no-op.
      obs.dispose();

      sub.cancel();
      sub2.cancel();
      sub3.cancel();
      async.flushMicrotasks();
    });
  });

  test('Observing a disposed observable document returns a fresh observer', () {
    fakeAsync((async) {
      _reset(async);
      final doc = Loon.collection<int>('items').doc('1');
      doc.create(1);
      flushBroadcasts(async);

      final obs = doc.observe();
      obs.dispose();
      final fresh = obs.observe();
      expect(identical(fresh, obs), false);

      final events = <int?>[];
      final sub = fresh.stream().listen((snap) => events.add(snap?.data));
      flushBroadcasts(async);
      doc.update(2);
      flushBroadcasts(async);

      expect(events, [1, 2]);

      sub.cancel();
      async.flushMicrotasks();
    });
  });

  test('Observing a disposed observable query returns a fresh observer', () {
    fakeAsync((async) {
      _reset(async);
      final items = Loon.collection<int>('items');
      items.doc('1').create(1);
      flushBroadcasts(async);

      final query = items.observe();
      query.dispose();
      final fresh = query.observe();
      expect(identical(fresh, query), false);

      final emissions = <List<int>>[];
      final sub = fresh.stream().listen((snaps) => emissions.add([for (final snap in snaps) snap.data]));
      flushBroadcasts(async);
      items.doc('2').create(2);
      flushBroadcasts(async);

      expect(emissions, [
        [1],
        [1, 2],
      ]);

      sub.cancel();
      async.flushMicrotasks();
    });
  });
}
