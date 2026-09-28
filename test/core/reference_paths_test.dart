import 'dart:math';

import 'package:flutter_test/flutter_test.dart';
import 'package:loon/loon.dart';

import '../models/test_persistor.dart';

class _PathPersistor extends TestPersistor {
  final Json data;

  _PathPersistor(this.data);

  @override
  Future<Json> hydrate([List<StoreReference>? refs]) async => data;
}

void main() {
  setUp(() => Loon.configure(persistor: null));
  tearDown(() async {
    Loon.unsubscribe();
    await Loon.clearAll(broadcast: false);
    Loon.configure(persistor: null);
  });

  group('Reference path assertions', () {
    test('asserts valid IDs and names through every construction API', () {
      final users = Loon.collection<int>('users');
      final user = users.doc('alice');
      for (final segment in [
        '',
        '_',
        '__',
        'a__b',
        'a_',
        '__values',
        'a___b'
      ]) {
        final constructors = <String, void Function()>{
          'collection': () => Loon.collection(segment),
          'document': () => users.doc(segment),
          'root document': () => Loon.doc(segment),
          'subcollection': () => user.subcollection(segment),
          'direct collection': () => Collection('', segment),
          'direct nested collection': () => Collection(user.path, segment),
          'direct document': () => Document(users.path, segment),
          'observable document': () =>
              ObservableDocument(users.path, segment, multicast: false),
        };
        for (final entry in constructors.entries) {
          expect(entry.value, throwsAssertionError,
              reason: '${entry.key}: "$segment"');
        }
      }
      expect(Loon.inspect()['store'], isEmpty);
      expect(Loon.inspect()['broadcastStore']['observerValues'], isEmpty);
    });

    test('keeps generated IDs and accepts leading and internal underscores',
        () {
      final users = Loon.collection<int>('user_profiles');
      final generated = [users.doc(), users.doc(null)];
      expect(generated[0].id, isNot(generated[1].id));
      for (final doc in generated) {
        expect(doc.id, isNotEmpty);
        expect(Document.fromPath(doc.path), doc);
      }
      for (final id in ['alice', '_alice', 'alice_smith', 'café', '鳥']) {
        final doc = users.doc(id)..create(42, broadcast: false);
        expect(doc.get()!.data, 42);
        expect(Document.fromPath(doc.path), doc);
      }
      final child =
          users.doc('_alice').subcollection<int>('_posts').doc('_one');
      child.create(99, broadcast: false);
      expect(child.path, 'user_profiles___alice___posts___one');
      expect(Document.fromPath<int>(child.path).get()!.data, 99);
    });

    test('direct constructors assert valid parent paths and hierarchy', () {
      for (final parent in [
        '',
        '__',
        'users_',
        'users__',
        'users____posts',
        'users__alice',
        'root__settings',
      ]) {
        expect(() => Document(parent, 'one'), throwsAssertionError,
            reason: 'document parent: "$parent"');
        expect(() => ObservableDocument(parent, 'one', multicast: false),
            throwsAssertionError,
            reason: 'observable parent: "$parent"');
      }
      for (final parent in [
        'users',
        'root',
        '__',
        'users__alice_',
        'users____alice',
        'users__alice__posts',
      ]) {
        expect(() => Collection(parent, 'posts'), throwsAssertionError,
            reason: 'collection parent: "$parent"');
      }
      expect(Collection('', 'users').path, 'users');
      expect(Collection('users__alice', 'posts').path, 'users__alice__posts');
      expect(Document('users__alice__posts', 'one').path,
          'users__alice__posts__one');
    });

    test('fromPath asserts before splitting invalid paths', () {
      for (final path in [
        '',
        '_',
        '__',
        '__users',
        'users__',
        'users____alice',
        'users__alice_',
        'users__alice____one',
      ]) {
        expect(() => Document.fromPath(path), throwsAssertionError,
            reason: 'document: "$path"');
        expect(() => Collection.fromPath(path), throwsAssertionError,
            reason: 'collection: "$path"');
      }
    });

    test('fromPath distinguishes collection and document paths', () {
      for (final path in ['users', 'root', 'users__alice__posts']) {
        expect(Collection.fromPath(path).path, path);
        expect(() => Document.fromPath(path), throwsAssertionError);
      }
      for (final path in [
        'users__alice',
        'root__settings',
        'users__alice__posts__one',
      ]) {
        expect(Document.fromPath(path).path, path);
        expect(() => Collection.fromPath(path), throwsAssertionError);
      }
      expect(Loon.doc('settings').path, 'root__settings');
      expect(Loon.doc('settings').subcollection('items').path,
          'root__settings__items');
    });

    test('formerly colliding names and IDs fail before writing data', () {
      final users = Loon.collection<int>('users');
      expect(() => users.doc(''), throwsAssertionError);
      expect(() => Loon.collection('users__alice'), throwsAssertionError);
      expect(() => users.doc('alice__posts'), throwsAssertionError);
      expect(
          () => Loon.collection('users_').doc('alice'), throwsAssertionError);

      final valid = users.doc('_alice')..create(42, broadcast: false);
      expect(valid.path, 'users___alice');
      expect(Document.fromPath<int>(valid.path).get()!.data, 42);
      expect(users.get().single.id, '_alice');
    });

    test('nested references round-trip without collection/document aliases',
        () {
      final random = Random(42);
      const names = ['a', 'b', '_c', 'd_e', 'root', '鳥'];
      String name() => names[random.nextInt(names.length)];
      for (var run = 0; run < 300; run++) {
        var collection = Loon.collection(name());
        for (var depth = 0; depth < 5; depth++) {
          final parsedCollection = Collection.fromPath(collection.path);
          expect(parsedCollection, collection);
          expect(parsedCollection.hashCode, collection.hashCode);
          expect(
              () => Document.fromPath(collection.path), throwsAssertionError);

          final doc = collection.doc(name());
          final parsedDoc = Document.fromPath(doc.path);
          expect(parsedDoc, doc);
          expect(parsedDoc.hashCode, doc.hashCode);
          expect(() => Collection.fromPath(doc.path), throwsAssertionError);
          collection = doc.subcollection(name());
        }
      }
    });

    test('hydrates valid paths with leading and internal underscores',
        () async {
      Loon.configure(persistor: _PathPersistor({'user_profiles___alice': 42}));
      await Loon.hydrate();
      expect(
          Loon.collection<int>('user_profiles').doc('_alice').get()!.data, 42);
    });

    test('hydration asserts valid persisted reference paths', () async {
      for (final path in [
        'users',
        'users__',
        'users____alice',
        'users__alice_'
      ]) {
        Loon.configure(persistor: _PathPersistor({path: 42}));
        await expectLater(Loon.hydrate(), throwsAssertionError, reason: path);
        expect(Loon.inspect()['store'], isEmpty);
      }
    });
  });
}
