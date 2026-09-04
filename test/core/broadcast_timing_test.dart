import 'package:fake_async/fake_async.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:loon/loon.dart';

import '../utils.dart';

/// Deterministic tests for broadcast batching, coalescing, and ordering.
///
/// Loon schedules a broadcast on a zero-duration timer so that all writes in a
/// single event-loop task are delivered to observers as one update. Testing
/// that behaviour with real time is inherently racy (it depends on a real timer
/// firing before the test's wait), which is a known source of flakiness in the
/// suite. These tests run under [fakeAsync] instead: virtual time is advanced
/// explicitly, so the broadcast timer and its microtask stream delivery fire
/// deterministically before each assertion, with no dependence on wall-clock
/// scheduling or CPU load.
///
/// (A dedicated file runs in its own test isolate, so the global store starts
/// clean and these virtual-time tests are isolated from the rest of the suite.)

void _reset(FakeAsync async) {
  Loon.unsubscribe();
  Loon.clearAll(broadcast: false);
  async.flushMicrotasks();
}

void main() {
  group('Broadcast batching and coalescing', () {
    test('Multiple writes in one task produce a single broadcast', () {
      fakeAsync((async) {
        _reset(async);
        final col = Loon.collection<int>('items');

        final emissions = <List<int>>[];
        final sub = col
            .stream()
            .listen((snaps) => emissions.add([for (final s in snaps) s.data]));
        flushBroadcasts(async); // initial emission

        col.doc('1').create(1);
        col.doc('2').create(2);
        col.doc('3').create(3);
        flushBroadcasts(async);

        // One emission for the initial value and exactly one for the batch.
        expect(emissions.length, 2);
        expect(emissions.last..sort(), [1, 2, 3]);

        sub.cancel();
        async.flushMicrotasks();
      });
    });

    test('Create then update in one task coalesces to the final value', () {
      fakeAsync((async) {
        _reset(async);
        final doc = Loon.collection<int>('items').doc('1');

        final emissions = <int?>[];
        final sub = doc.stream().listen((snap) => emissions.add(snap?.data));
        flushBroadcasts(async); // initial null

        doc.create(1);
        doc.update(2);
        flushBroadcasts(async);

        // The create and update collapse into a single emission of the final value.
        expect(emissions, [null, 2]);

        sub.cancel();
        async.flushMicrotasks();
      });
    });

    test('Writes in separate tasks produce separate broadcasts', () {
      fakeAsync((async) {
        _reset(async);
        final doc = Loon.collection<int>('items').doc('1');

        final emissions = <int?>[];
        final sub = doc.stream().listen((snap) => emissions.add(snap?.data));
        flushBroadcasts(async); // initial null

        doc.create(1);
        flushBroadcasts(async);
        doc.update(2);
        flushBroadcasts(async);
        doc.update(3);
        flushBroadcasts(async);

        expect(emissions, [null, 1, 2, 3]);

        sub.cancel();
        async.flushMicrotasks();
      });
    });

    test('An unchanged update does not rebroadcast', () {
      fakeAsync((async) {
        _reset(async);
        final doc = Loon.collection<int>('items').doc('1');

        final emissions = <int?>[];
        final sub = doc.stream().listen((snap) => emissions.add(snap?.data));
        flushBroadcasts(async); // initial null

        doc.create(1);
        flushBroadcasts(async);
        doc.update(1); // same value
        flushBroadcasts(async);

        // No emission for the no-op update.
        expect(emissions, [null, 1]);

        sub.cancel();
        async.flushMicrotasks();
      });
    });
  });
}
