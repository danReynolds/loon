import 'package:fake_async/fake_async.dart';
import 'package:flutter/foundation.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:loon/loon.dart';

import '../models/test_user_model.dart';
import '../utils.dart';

/// Tests for [Document.rebroadcast] and for dependents being rebroadcast when the documents they
/// depend on are written or deleted. A touched document is re-evaluated by its observers: document
/// observers re-read it and queries re-evaluate its membership and order.
///
/// These run under [fakeAsync] so that the broadcast timer is flushed deterministically.



/// Runs [body] while capturing the errors reported through [FlutterError.reportError].
List<Object> _captureErrors(void Function() body) {
  final errors = <Object>[];
  final onError = FlutterError.onError;
  FlutterError.onError = (details) => errors.add(details.exception);
  try {
    body();
  } finally {
    FlutterError.onError = onError;
  }
  return errors;
}

void main() {

  group('Document.rebroadcast', () {
    test('Re-reads a document written without a broadcast', () {
      fakeAsync((async) {
        resetStore(async);
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
        resetStore(async);
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
        resetStore(async);
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

    test('Propagates rebuilt dependencies', () {
      fakeAsync((async) {
        resetStore(async);
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

        final events = <String?>[];
        final sub = post.stream().listen((snap) => events.add(snap?.data));
        flushBroadcasts(async);

        // A rebroadcast does not rebuild dependencies on its own.
        dependsOnSecond = true;
        post.rebroadcast();
        flushBroadcasts(async);
        expect(post.dependencies(), {users.doc('1')});

        post.rebuildDependencies();
        post.rebroadcast();
        flushBroadcasts(async);
        expect(post.dependencies(), {users.doc('2')});

        // The old dependency no longer rebroadcasts the post, and the new one does.
        users.doc('1').update('User 1 updated');
        flushBroadcasts(async);
        expect(events, ['Post 1', 'Post 1', 'Post 1']);

        users.doc('2').update('User 2 updated');
        flushBroadcasts(async);
        expect(events, ['Post 1', 'Post 1', 'Post 1', 'Post 1']);

        sub.cancel();
        async.flushMicrotasks();
      });
    });

    test('Emits touched, added and removed change events on queries', () {
      fakeAsync((async) {
        resetStore(async);
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

    test('Does nothing for a document that does not exist', () {
      fakeAsync((async) {
        resetStore(async);
        TestUserModel.store.doc('1').create(TestUserModel('a'));
        flushBroadcasts(async);

        final doc = TestUserModel.store.doc('missing');
        final query = TestUserModel.store.observe();
        final events = <String?>[];
        final collectionEvents = <int>[];
        final sub = doc.stream().listen((snap) => events.add(snap?.data.name));
        final sub2 = query.stream().listen((snaps) => collectionEvents.add(snaps.length));
        flushBroadcasts(async);

        doc.rebroadcast();

        // There is no value to re-evaluate, so nothing is scheduled and the cached values of
        // the collection's queries are left intact.
        expect(query.isDirty, false);
        flushBroadcasts(async);

        expect(events, [null]);
        expect(collectionEvents, [1]);

        sub.cancel();
        sub2.cancel();
        async.flushMicrotasks();
      });
    });
  });

  group('Dependencies', () {
    test('Re-evaluates dependents in queries when a dependency changes', () {
      fakeAsync((async) {
        resetStore(async);
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

    test('Re-evaluates dependents when a dependency collection is deleted', () {
      fakeAsync((async) {
        resetStore(async);
        final users = Loon.collection<bool>('users');
        final posts = Loon.collection<String>(
          'posts',
          dependenciesBuilder: (snap) => {users.doc(snap.data)},
        );
        users.doc('u1').create(true);
        users.doc('u2').create(true);
        posts.doc('p1').create('u1');
        posts.doc('p2').create('u2');
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
          ['p1', 'p2'],
          [],
        ]);

        sub.cancel();
        async.flushMicrotasks();
      });
    });

    test("Re-evaluates dependents of a deleted document's subcollection documents", () {
      fakeAsync((async) {
        resetStore(async);
        final users = Loon.collection<String>('users');
        final friends = users.doc('u1').subcollection<bool>('friends');
        final posts = Loon.collection<String>(
          'posts',
          dependenciesBuilder: (snap) => {friends.doc(snap.data)},
        );
        users.doc('u1').create('User 1');
        friends.doc('f1').create(true);
        posts.doc('p1').create('f1');
        flushBroadcasts(async);

        // Posts whose tagged friend still exists.
        final tagged = posts.where((snap) => friends.doc(snap.data).exists()).observe();
        final emissions = <List<String>>[];
        final sub = tagged.stream().listen(
          (snaps) => emissions.add([for (final snap in snaps) snap.id]),
        );
        flushBroadcasts(async);

        // Deleting the user deletes its friends subcollection, so the post's dependency is gone.
        users.doc('u1').delete();
        flushBroadcasts(async);

        expect(emissions, [
          ['p1'],
          [],
        ]);

        sub.cancel();
        async.flushMicrotasks();
      });
    });

    test('Does not touch dependents that are deleted along with their dependency', () {
      fakeAsync((async) {
        resetStore(async);
        final items = Loon.collection<String>(
          'items',
          dependenciesBuilder: (snap) =>
              snap.id == '2' ? {Loon.collection<String>('items').doc('1')} : null,
        );
        final outside = Loon.collection<String>(
          'outside',
          dependenciesBuilder: (snap) => {items.doc('1')},
        );
        items.doc('1').create('one');
        // Depends on a sibling that is deleted along with it.
        items.doc('2').create('two');
        // Depends on the deleted document from outside the deleted collection.
        outside.doc('x').create('x');
        flushBroadcasts(async);

        final insideChanges = <String>[];
        final outsideChanges = <String>[];
        final sub = items.doc('2').streamChanges().listen(
          (change) => insideChanges.add(change.event.name),
        );
        final sub2 = outside.doc('x').streamChanges().listen(
          (change) => outsideChanges.add(change.event.name),
        );
        flushBroadcasts(async);

        items.delete();
        flushBroadcasts(async);

        // The document deleted with the collection is reported as removed rather than touched,
        // while the dependent outside of the collection is touched.
        expect(insideChanges, ['removed']);
        expect(outsideChanges, ['touched']);

        sub.cancel();
        sub2.cancel();
        async.flushMicrotasks();
      });
    });

    test("Clearing a document's dependencies keeps its subcollection documents' dependencies", () {
      fakeAsync((async) {
        resetStore(async);
        final users = Loon.collection<String>('users');
        users.doc('a1').create('a');
        users.doc('a2').create('b');
        final posts = Loon.collection<Map<String, String>>(
          'posts',
          dependenciesBuilder: (snap) =>
              snap.data['userId'] != null ? {users.doc(snap.data['userId']!)} : null,
        );
        final comments = posts.doc('1').subcollection<String>(
          'comments',
          dependenciesBuilder: (snap) => {users.doc(snap.data)},
        );
        posts.doc('1').create({'userId': 'a1'});
        comments.doc('c1').create('a1');
        flushBroadcasts(async);

        // The post no longer has dependencies of its own.
        posts.doc('1').update({'text': 'x'});
        flushBroadcasts(async);

        expect(comments.doc('c1').dependencies(), {users.doc('a1')});

        // Switching the comment's dependency still removes it from the old one.
        comments.doc('c1').update('a2');
        flushBroadcasts(async);
        final events = <String?>[];
        final sub = comments.doc('c1').stream().listen((snap) => events.add(snap?.data));
        flushBroadcasts(async);

        users.doc('a1').update('a updated');
        flushBroadcasts(async);
        expect(events, ['a2']);

        users.doc('a2').update('b updated');
        flushBroadcasts(async);
        expect(events, ['a2', 'a2']);

        sub.cancel();
        async.flushMicrotasks();
      });
    });

    test('Deleting a document drops the dependents under it from the index', () {
      fakeAsync((async) {
        resetStore(async);
        final accounts = Loon.collection<String>('accounts');
        final account = accounts.doc('a1');
        final transactions = account.subcollection<String>(
          'transactions',
          dependenciesBuilder: (snap) => {account},
        );
        final reports = Loon.collection<String>(
          'reports',
          dependenciesBuilder: (snap) => {account},
        );
        account.create('Account 1');
        transactions.doc('t1').create('tx');
        transactions.doc('t2').create('tx');
        reports.doc('r1').create('report');
        flushBroadcasts(async);

        final reportEvents = <String>[];
        final sub = reports.doc('r1').streamChanges().listen(
          (change) => reportEvents.add(change.event.name),
        );
        flushBroadcasts(async);

        account.delete();
        flushBroadcasts(async);

        // The transactions were deleted with the account and are no longer indexed as its
        // dependents, while the report outside of it was touched and remains indexed.
        expect(reportEvents, ['touched']);
        expect(Loon.inspect()['dependentsStore'], {
          'accounts': {
            '__values': {
              'a1': {reports.doc('r1')},
            }
          }
        });

        sub.cancel();
        async.flushMicrotasks();
      });
    });

    test('Re-creating a document with different dependencies drops its old ones', () {
      fakeAsync((async) {
        resetStore(async);
        final users = Loon.collection<String>('users');
        final posts = Loon.collection<String>(
          'posts',
          dependenciesBuilder: (snap) => {users.doc(snap.data)},
        );
        users.doc('u1').create('User 1');
        users.doc('u2').create('User 2');
        posts.doc('p1').create('u1');
        flushBroadcasts(async);

        // The post is deleted and re-created depending on a different user.
        posts.replace([DocumentSnapshot(doc: posts.doc('p1'), data: 'u2')]);
        flushBroadcasts(async);

        expect(Loon.inspect()['dependentsStore'], {
          'users': {
            '__values': {
              'u2': {posts.doc('p1')},
            }
          }
        });

        final events = <String>[];
        final sub = posts.doc('p1').streamChanges().listen(
          (change) => events.add(change.event.name),
        );
        flushBroadcasts(async);

        users.doc('u1').update('User 1 updated');
        flushBroadcasts(async);
        expect(events, isEmpty, reason: 'the old dependency no longer rebroadcasts the post');

        users.doc('u2').update('User 2 updated');
        flushBroadcasts(async);
        expect(events, ['touched']);

        sub.cancel();
        async.flushMicrotasks();
      });
    });
  });

  group('Broadcast', () {
    test('A query whose filter throws is reset and does not affect other observers', () {
      final errors = _captureErrors(() {
        fakeAsync((async) {
          resetStore(async);
          bool shouldThrow = false;
          final items = Loon.collection<int>('items');
          items.doc('1').create(1);
          flushBroadcasts(async);

          // Observers process a broadcast in the order they were created, so the throwing
          // observer runs before the healthy one.
          final throwing = items.where((snap) {
            if (shouldThrow) {
              throw StateError('Filter failed');
            }
            return true;
          }).observe();
          final healthy = items.observe();
          final other = Loon.collection<int>('other').doc('1');
          final healthyEmissions = <List<int>>[];
          final otherEvents = <int?>[];
          final sub = throwing.stream().listen((_) {});
          final sub2 = healthy.stream().listen(
            (snaps) => healthyEmissions.add([for (final snap in snaps) snap.data]),
          );
          final sub3 = other.stream().listen((snap) => otherEvents.add(snap?.data));
          flushBroadcasts(async);

          shouldThrow = true;
          items.doc('1').update(2);
          flushBroadcasts(async);

          // The throwing query is reset, and the remaining observers and later broadcasts
          // are unaffected.
          expect(throwing.isDirty, true);
          shouldThrow = false;
          other.create(7);
          flushBroadcasts(async);

          expect(healthyEmissions, [
            [1],
            [2],
          ]);
          expect(otherEvents, [null, 7]);

          sub.cancel();
          sub2.cancel();
          sub3.cancel();
          async.flushMicrotasks();
        });
      });

      // The error is reported.
      expect(errors, [isStateError]);
    });
  });
}
