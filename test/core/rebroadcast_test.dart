import 'dart:async';

import 'package:fake_async/fake_async.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:loon/loon.dart';

import '../models/test_user_model.dart';
import '../utils.dart';

/// Tests for [Document.rebroadcast], which is treated as a write of the document's current value
/// that is not persisted: observers re-read the document, queries re-evaluate it, and its
/// dependencies are rebuilt.
///
/// These run under [fakeAsync] so that the broadcast timer is flushed deterministically.

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

  group('Document.rebroadcast', () {
    test('Re-reads a document written without a broadcast', () {
      fakeAsync((async) {
        _reset(async);
        final doc = TestUserModel.store.doc('1');
        doc.create(TestUserModel('a'));
        flushBroadcasts(async);

        final docEvents = <String?>[];
        final collectionEvents = <List<String>>[];
        final sub = doc.stream().listen((snap) => docEvents.add(snap?.data.name));
        final sub2 = TestUserModel.store.stream().listen(
          (snaps) => collectionEvents.add([for (final snap in snaps) snap.data.name]),
        );
        flushBroadcasts(async);

        doc.update(TestUserModel('b'), broadcast: false);
        doc.rebroadcast();
        flushBroadcasts(async);

        // Both the document and the collection observers deliver the current value.
        expect(docEvents, ['a', 'b']);
        expect(collectionEvents, [
          ['a'],
          ['b'],
        ]);

        sub.cancel();
        sub2.cancel();
        async.flushMicrotasks();
      });
    });

    test('Re-evaluates query membership from state outside of the store', () {
      fakeAsync((async) {
        _reset(async);
        final flags = <String, bool>{};
        final items = Loon.collection<String>('items');
        items.doc('1').create('a');
        items.doc('2').create('b');
        flushBroadcasts(async);

        final flagged = items.where((snap) => flags[snap.id] ?? false).observe();
        final unrelated = items.where((snap) => snap.id == 'none').observe();
        final emissions = <List<String>>[];
        final unrelatedEmissions = <int>[];
        final sub = flagged.stream().listen(
          (snaps) => emissions.add([for (final snap in snaps) snap.id]),
        );
        final sub2 = unrelated.stream().listen((snaps) => unrelatedEmissions.add(snaps.length));
        flushBroadcasts(async);

        // The document now satisfies the filter because of a change outside of the store.
        flags['1'] = true;
        items.doc('1').rebroadcast();

        // A read before the broadcast already reflects the change.
        expect([for (final snap in flagged.get()) snap.id], ['1']);
        flushBroadcasts(async);

        // It no longer does.
        flags['1'] = false;
        items.doc('1').rebroadcast();
        flushBroadcasts(async);

        expect(emissions, [
          [],
          ['1'],
          [],
        ]);
        // A query that the document can never be part of is not rebroadcast.
        expect(unrelatedEmissions, [0]);

        sub.cancel();
        sub2.cancel();
        async.flushMicrotasks();
      });
    });

    test('Re-sorts a query whose sort reads state outside of the store', () {
      fakeAsync((async) {
        _reset(async);
        bool reverse = false;
        final items = Loon.collection<int>('items');
        items.doc('1').create(1);
        items.doc('2').create(2);
        flushBroadcasts(async);

        final sorted = items
            .sortBy(
              (a, b) => reverse ? b.data.compareTo(a.data) : a.data.compareTo(b.data),
            )
            .observe();
        final emissions = <List<int>>[];
        final sub = sorted.stream().listen(
          (snaps) => emissions.add([for (final snap in snaps) snap.data]),
        );
        flushBroadcasts(async);

        reverse = true;
        items.doc('1').rebroadcast();
        flushBroadcasts(async);

        expect(emissions, [
          [1, 2],
          [2, 1],
        ]);

        sub.cancel();
        async.flushMicrotasks();
      });
    });

    test("Rebuilds the document's dependencies", () {
      fakeAsync((async) {
        _reset(async);
        bool dependsOnSecond = false;
        final users = Loon.collection<String>('users');
        final posts = Loon.collection<String>(
          'posts',
          dependenciesBuilder: (snap) => {dependsOnSecond ? users.doc('2') : users.doc('1')},
        );
        users.doc('1').create('User 1');
        users.doc('2').create('User 2');
        final post = posts.doc('1');
        post.create('Post 1');
        flushBroadcasts(async);

        expect(post.dependencies(), {users.doc('1')});

        dependsOnSecond = true;
        post.rebroadcast();
        flushBroadcasts(async);

        expect(post.dependencies(), {users.doc('2')});

        // The new dependency now causes the post to be rebroadcast.
        final events = <String?>[];
        final sub = post.stream().listen((snap) => events.add(snap?.data));
        flushBroadcasts(async);
        users.doc('2').update('User 2 updated');
        flushBroadcasts(async);

        expect(events, ['Post 1', 'Post 1']);

        sub.cancel();
        async.flushMicrotasks();
      });
    });

    test('Emits touched, added and removed change events on queries', () {
      fakeAsync((async) {
        _reset(async);
        final flags = <String, bool>{'1': true};
        final items = Loon.collection<String>('items');
        items.doc('1').create('a');
        items.doc('2').create('b');
        flushBroadcasts(async);

        final flagged = items.where((snap) => flags[snap.id] ?? false).observe();
        final changes = <String>[];
        final sub = flagged.streamChanges().listen(
          (snaps) => changes.addAll([for (final snap in snaps) '${snap.id}:${snap.event.name}']),
        );
        flushBroadcasts(async);

        // Still a member.
        items.doc('1').rebroadcast();
        // Enters the result set.
        flags['2'] = true;
        items.doc('2').rebroadcast();
        flushBroadcasts(async);

        // Leaves the result set.
        flags['1'] = false;
        items.doc('1').rebroadcast();
        flushBroadcasts(async);

        expect(changes, ['1:touched', '2:added', '1:removed']);

        sub.cancel();
        async.flushMicrotasks();
      });
    });

    test('Notifies the listeners of a document that does not exist', () {
      fakeAsync((async) {
        _reset(async);
        final doc = TestUserModel.store.doc('missing');
        final events = <String?>[];
        final collectionEvents = <int>[];
        final sub = doc.stream().listen((snap) => events.add(snap?.data.name));
        final sub2 = TestUserModel.store.stream().listen(
          (snaps) => collectionEvents.add(snaps.length),
        );
        flushBroadcasts(async);

        doc.rebroadcast();
        flushBroadcasts(async);

        // There is no value to re-evaluate, so the document's listeners are notified again
        // and the collection is unaffected.
        expect(events, [null, null]);
        expect(collectionEvents, [0]);

        sub.cancel();
        sub2.cancel();
        async.flushMicrotasks();
      });
    });
  });

  group('Dependencies', () {
    test('Re-evaluates dependents in queries when a dependency changes', () {
      fakeAsync((async) {
        _reset(async);
        final users = Loon.collection<bool>('users');
        final posts = Loon.collection<String>(
          'posts',
          dependenciesBuilder: (snap) => {users.doc(snap.data)},
        );
        users.doc('u1').create(true);
        posts.doc('p1').create('u1');
        flushBroadcasts(async);

        // Posts whose user is active. The filter reads the dependency, so the post must be
        // re-evaluated whenever its user changes.
        final active = posts
            .where((snap) => users.doc(snap.data).get()?.data ?? false)
            .observe();
        final emissions = <List<String>>[];
        final sub = active.stream().listen(
          (snaps) => emissions.add([for (final snap in snaps) snap.id]),
        );
        flushBroadcasts(async);

        users.doc('u1').update(false);
        flushBroadcasts(async);
        users.doc('u1').update(true);
        flushBroadcasts(async);

        expect(emissions, [
          ['p1'],
          [],
          ['p1'],
        ]);

        sub.cancel();
        async.flushMicrotasks();
      });
    });

    test('Re-evaluates a query when a path that its documents depend on is deleted', () {
      fakeAsync((async) {
        _reset(async);
        final users = Loon.collection<bool>('users');
        final posts = Loon.collection<String>(
          'posts',
          dependenciesBuilder: (snap) => {users.doc(snap.data)},
        );
        users.doc('u1').create(true);
        posts.doc('p1').create('u1');
        flushBroadcasts(async);

        final active = posts
            .where((snap) => users.doc(snap.data).get()?.data ?? false)
            .observe();
        final emissions = <List<String>>[];
        final sub = active.stream().listen(
          (snaps) => emissions.add([for (final snap in snaps) snap.id]),
        );
        flushBroadcasts(async);

        users.delete();
        flushBroadcasts(async);

        expect(emissions, [
          ['p1'],
          [],
        ]);

        sub.cancel();
        async.flushMicrotasks();
      });
    });
  });

  group('Broadcast', () {
    test(
      'An observer that throws does not prevent other observers from processing the broadcast',
      () {
        final errors = <Object>[];

        runZonedGuarded(() {
          fakeAsync((async) {
            _reset(async);
            bool shouldThrow = false;
            final items = Loon.collection<int>('items');
            items.doc('1').create(1);
            flushBroadcasts(async);

            // Observers process a broadcast in the order they were created, so both throwing
            // observers run before the one that does not throw.
            final throwingA = items.where((snap) {
              if (shouldThrow) {
                throw StateError('Filter A failed');
              }
              return true;
            }).observe();
            final throwingB = items.where((snap) {
              if (shouldThrow) {
                throw StateError('Filter B failed');
              }
              return true;
            }).observe();
            final other = items.observe();
            final otherEvents = <List<int>>[];
            final subA = throwingA.stream().listen((_) {});
            final subB = throwingB.stream().listen((_) {});
            final sub = other.stream().listen(
              (snaps) => otherEvents.add([for (final snap in snaps) snap.data]),
            );
            flushBroadcasts(async);

            shouldThrow = true;
            items.doc('1').update(2);
            flushBroadcasts(async);

            // The remaining observer still processed the broadcast.
            expect(otherEvents, [
              [1],
              [2],
            ]);

            subA.cancel();
            subB.cancel();
            sub.cancel();
            async.flushMicrotasks();
          });
        }, (error, stack) => errors.add(error));

        // Every error is surfaced.
        expect(errors, [isStateError, isStateError]);
      },
    );

    test('An observer that throws does not prevent subsequent broadcasts', () {
      // fake_async runs timer callbacks guarded, so the error thrown by the observer is
      // delivered to the zone's error handler rather than thrown from the broadcast flush.
      final errors = <Object>[];

      runZonedGuarded(() {
        fakeAsync((async) {
          _reset(async);
          bool shouldThrow = false;
          final items = Loon.collection<int>('items');
          items.doc('1').create(1);
          flushBroadcasts(async);

          final throwing = items.where((snap) {
            if (shouldThrow) {
              throw StateError('Filter failed');
            }
            return true;
          }).observe();
          final other = Loon.collection<int>('other').doc('1');
          final otherEvents = <int?>[];
          final sub = throwing.stream().listen((_) {});
          final sub2 = other.stream().listen((snap) => otherEvents.add(snap?.data));
          flushBroadcasts(async);

          // The filter throws while this broadcast is processed.
          shouldThrow = true;
          items.doc('1').update(2);
          flushBroadcasts(async);

          // Later broadcasts are still delivered.
          shouldThrow = false;
          other.create(7);
          flushBroadcasts(async);

          expect(otherEvents, [null, 7]);

          sub.cancel();
          sub2.cancel();
          async.flushMicrotasks();
        });
      }, (error, stack) => errors.add(error));

      expect(errors, [isStateError]);
    });
  });
}
