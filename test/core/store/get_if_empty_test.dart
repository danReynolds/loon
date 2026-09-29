import 'dart:convert';

import 'package:flutter_test/flutter_test.dart';
import 'package:loon/src/store/store.dart';

void main() {
  for (final (name, createStore) in [
    ('ValueStore', ValueStore<String>.new),
    ('ValueRefStore', ValueRefStore<String>.new),
  ]) {
    group('$name get(ifEmpty:)', () {
      test('initializes missing paths once and leaves ordinary reads unchanged',
          () {
        final store = createStore();
        expect(store.get('missing__branch'), isNull);
        expect(store.isEmpty, isTrue);

        var calls = 0;
        for (final path in [
          '',
          'users__alice',
          'users___bob',
          'orgs__one__users__c'
        ]) {
          expect(
              store.get(path, ifEmpty: () => 'value${++calls}'), 'value$calls');
          expect(store.get(path), 'value$calls');
          expect(store.get(path, ifEmpty: () => fail('already initialized')),
              'value$calls');
        }
        expect(calls, 4);
        final before = jsonDecode(jsonEncode(store.inspect()));
        expect(store.get('new__branch__value'), isNull);
        expect(store.inspect(), before);
      });

      test('throwing initializers leave existing and missing parents unchanged',
          () {
        final store = createStore()..write('users__alice', 'Alice');
        final before = jsonDecode(jsonEncode(store.inspect()));
        for (final path in ['users__bob', 'new__branch__value']) {
          expect(
              () => store.get(path, ifEmpty: () => throw StateError('failed')),
              throwsStateError);
          expect(store.inspect(), before);
        }
      });

      test(
          'stores the result after an initializer clears or deletes its parent',
          () {
        for (final clear in [false, true]) {
          final store = createStore()..write('users__alice', 'Alice');
          expect(
            store.get('users__bob', ifEmpty: () {
              if (clear) {
                store.clear();
              } else {
                store.delete('users');
              }
              return 'Bob';
            }),
            'Bob',
          );
          expect(store.get('users__bob'), 'Bob');
          expect(store.inspect(),
              (createStore()..write('users__bob', 'Bob')).inspect());
        }
      });
    });
  }

  test('ValueStore returns the stored instance and preserves sibling writes',
      () {
    final store = ValueStore<Set<int>>()..write('users__alice', {1});
    final created = <int>{};
    final value = store.get('users__bob', ifEmpty: () {
      store.write('users__carol', {3});
      return created;
    })!;
    value.add(2);
    expect(identical(value, created), isTrue);
    expect(identical(store.get('users__bob'), created), isTrue);
    expect(store.extract(), {
      'users__alice': {1},
      'users__bob': {2},
      'users__carol': {3},
    });
  });

  test('ValueStore treats null as empty, including a null initializer result',
      () {
    final store = ValueStore<String?>()..write('users__alice', null);
    expect(store.get('users__alice', ifEmpty: () => 'Alice'), 'Alice');
    expect(store.get('users__bob', ifEmpty: () => null), isNull);
    expect(store.extract().containsKey('users__bob'), isTrue);
    expect(store.get('users__bob', ifEmpty: () => 'Bob'), 'Bob');
  });

  test('ValueRefStore counts initialized values once and removes their refs',
      () {
    final store = ValueRefStore<String>();
    store.get('users__alice', ifEmpty: () => 'shared');
    store.get('users__bob', ifEmpty: () => 'shared');
    store.get('users__alice', ifEmpty: () => fail('already initialized'));
    expect(store.getRefs(), {'shared': 2});
    expect(store.getRefs('users'), {'shared': 2});
    store.delete('users__alice');
    expect(store.getRefs(), {'shared': 1});
    store.delete('users');
    expect(store.isEmpty, isTrue);
    expect(store.getRefs(), isNull);
  });
}
