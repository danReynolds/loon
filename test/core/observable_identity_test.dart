import 'package:fake_async/fake_async.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:loon/loon.dart';

import '../utils.dart';

/// An [ObservableDocument] is equal to the document it observes, so writes made through an
/// observable handle are matched by plain document references in the structures keyed by
/// documents, while observer instances remain distinct in the broadcast manager.


void main() {

  test('An observable document is equal to the document it observes', () {
    final doc = Loon.collection<int>('items').doc('1');
    final obs = doc.observe();

    expect(obs == doc, true);
    expect(doc == obs, true);
    expect(obs.hashCode, doc.hashCode);
    expect({doc}.contains(obs), true);

    obs.dispose();
  });

  test('Observables of the same document are distinct observers', () {
    fakeAsync((async) {
      resetStore(async);
      final doc = Loon.collection<int>('items').doc('1');
      final first = <int?>[];
      final second = <int?>[];
      final sub1 = doc.stream().listen((snap) => first.add(snap?.data));
      final sub2 = doc.stream().listen((snap) => second.add(snap?.data));
      flushBroadcasts(async);

      doc.create(1);
      flushBroadcasts(async);

      expect(first, [null, 1]);
      expect(second, [null, 1]);

      sub1.cancel();
      sub2.cancel();
      async.flushMicrotasks();
    });
  });

  test('A document written through an observable is matched by queries', () {
    fakeAsync((async) {
      resetStore(async);
      final items = Loon.collection<String>('items');
      final query = items.observe();
      final emissions = <List<String>>[];
      final sub = query.stream().listen(
        (snaps) => emissions.add([for (final snap in snaps) '${snap.id}=${snap.data}']),
      );
      flushBroadcasts(async);

      final obs = items.doc('1').observe();
      obs.create('x');
      flushBroadcasts(async);
      // Updated and deleted through the plain document.
      items.doc('1').update('y');
      flushBroadcasts(async);
      items.doc('1').delete();
      flushBroadcasts(async);

      expect(emissions, [
        [],
        ['1=x'],
        ['1=y'],
        [],
      ]);
      expect(query.get(), isEmpty);

      sub.cancel();
      obs.dispose();
      async.flushMicrotasks();
    });
  });

  test('A dependent written through an observable is removed from its old dependency', () {
    fakeAsync((async) {
      resetStore(async);
      final users = Loon.collection<String>('users');
      final posts = Loon.collection<String>(
        'posts',
        dependenciesBuilder: (snap) => {users.doc(snap.data)},
      );
      users.doc('u1').create('a');
      users.doc('u2').create('b');
      final obs = posts.doc('p1').observe();
      final events = <String?>[];
      final sub = obs.stream().listen((snap) => events.add(snap?.data));
      flushBroadcasts(async);

      obs.create('u1');
      flushBroadcasts(async);
      // Switched through the plain document.
      posts.doc('p1').update('u2');
      flushBroadcasts(async);
      final before = events.length;

      users.doc('u1').update('a updated');
      flushBroadcasts(async);
      expect(events.length, before, reason: 'the old dependency no longer rebroadcasts the post');

      users.doc('u2').update('b updated');
      flushBroadcasts(async);
      expect(events.length, before + 1);

      sub.cancel();
      async.flushMicrotasks();
    });
  });
}
