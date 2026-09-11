import 'package:fake_async/fake_async.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:loon/loon.dart';

import '../utils.dart';

/// A disposed observer stops delivering, its closed streams cannot be listened to again, and
/// observing it again returns a fresh observer.


void main() {

  test('A disposed observer stops delivering and cannot be listened to again', () {
    fakeAsync((async) {
      resetStore(async);
      final doc = Loon.collection<int>('items').doc('1');
      doc.create(1);
      flushBroadcasts(async);

      final obs = doc.observe();
      final events = <int?>[];
      final changes = <BroadcastEvents>[];
      final sub = obs.stream().listen((snap) => events.add(snap?.data));
      final sub2 = obs.streamChanges().listen((change) => changes.add(change.event));
      flushBroadcasts(async);

      obs.dispose();
      doc.update(2);
      flushBroadcasts(async);

      expect(events, [1]);
      expect(changes, isEmpty);
      // The disposed observer's streams are closed and cannot be listened to again.
      expect(() => obs.stream().listen((_) {}), throwsStateError);
      expect(() => obs.streamChanges().listen((_) {}), throwsStateError);
      // Disposing again is a no-op.
      obs.dispose();

      sub.cancel();
      sub2.cancel();
      async.flushMicrotasks();
    });
  });

  test('Observing a disposed observable document returns a fresh observer', () {
    fakeAsync((async) {
      resetStore(async);
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
      resetStore(async);
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
