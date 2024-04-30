import 'package:flutter_test/flutter_test.dart';
import 'package:loon/loon.dart';

void main() {
  group('write', () {
    test('Writes the value to the given path and increments the ref count', () {
      final store = IndexedRefValueStore<String>();

      store.write('users', 'Collection value');
      store.write('users__1', 'Dan');
      store.write('users__2', 'Sonja');
      store.write('users__1__messages__2', 'Hey there!');

      expect(store.inspect(), {
        "__refs": {
          "Collection value": 1,
        },
        "__values": {
          "users": "Collection value",
        },
        "users": {
          "__refs": {
            "Dan": 1,
            "Sonja": 1,
          },
          "__values": {
            "1": "Dan",
            "2": "Sonja",
          },
          "1": {
            "messages": {
              "__refs": {
                "Hey there!": 1,
              },
              "__values": {
                "2": "Hey there!",
              },
            },
          },
        }
      });
    });

    test('Decrements the old value when a path is updated', () {
      final store = IndexedRefValueStore<String>();

      store.write('users__1', 'Test');
      store.write('users__2', 'Test');

      expect(store.inspect(), {
        "users": {
          "__refs": {
            'Test': 2,
          },
          "__values": {
            "1": 'Test',
            "2": 'Test',
          },
        },
      });

      store.write('users__2', 'Test 2');

      expect(store.inspect(), {
        "users": {
          "__refs": {
            'Test': 1,
            'Test 2': 1,
          },
          "__values": {
            "1": 'Test',
            "2": 'Test 2',
          },
        },
      });

      store.write('users__1', 'Test 2');

      expect(store.inspect(), {
        "users": {
          "__refs": {
            'Test 2': 2,
          },
          "__values": {
            "1": 'Test 2',
            "2": 'Test 2',
          },
        },
      });
    });
  });

  group('getRef', () {
    test('Retrieves ref count for the value at the given path', () {
      final store = IndexedRefValueStore<String>();

      store.write('users__1', 'Dan');
      store.write('users__2', 'Sonja');
      store.write('users__1__friends__1', 'Nik');

      expect(store.getRefCount('users', 'Dan'), 1);
      expect(store.getRefCount('users', 'Sonja'), 1);
      expect(store.getRefCount('users__1__friends', 'Nik'), 1);

      store.write('users__3', 'Dan');

      expect(store.getRefCount('users', 'Dan'), 2);
    });
  });

  group('get', () {
    test('Retrieves the value at the given path', () {
      final store = IndexedValueStore<String>();

      store.write('users__1', 'Dan');
      store.write('users__2', 'Sonja');
      store.write('users__1__friends__1', 'Nik');

      expect(store.get('users__1'), 'Dan');
      expect(store.get('users__2'), 'Sonja');
      expect(store.get('users__1__friends__1'), 'Nik');
    });
  });

  group('getAll', () {
    test('Retrieves all of the values of the children of the given path', () {
      final store = IndexedRefValueStore<String>();

      store.write('users__1', 'Dan');
      store.write('users__2', 'Sonja');
      store.write('users__1__friends__1', 'Nik');

      expect(store.getAll('users__1'), null);
      expect(store.getAll('users__2'), null);
      expect(store.getAll('users'), {
        "1": "Dan",
        "2": "Sonja",
      });
      expect(store.getAll('users__1__friends'), {
        "1": "Nik",
      });
    });
  });

  group('delete', () {
    test(
        'Removes the value at the given path from the store and decrements the ref count.',
        () {
      final store = IndexedRefValueStore<String>();

      store.write('users__1', 'Dan');
      store.write('users__2', 'Sonja');
      store.write('users__1__friends__1', 'Nik');

      expect(store.inspect(), {
        "users": {
          "__refs": {
            "Dan": 1,
            "Sonja": 1,
          },
          "__values": {
            "1": "Dan",
            "2": "Sonja",
          },
          "1": {
            "friends": {
              "__refs": {
                "Nik": 1,
              },
              "__values": {
                "1": "Nik",
              },
            },
          },
        },
      });

      store.delete('users__1');

      expect(store.inspect(), {
        "users": {
          "__refs": {
            "Sonja": 1,
          },
          "__values": {
            "2": "Sonja",
          },
        },
      });

      store.delete('users__2');

      expect(store.inspect(), {});

      store.write('users__1', 'Dan');
      store.write('users__2', 'Sonja');

      expect(store.inspect(), {
        "users": {
          "__refs": {
            "Dan": 1,
            "Sonja": 1,
          },
          "__values": {
            "1": "Dan",
            "2": "Sonja",
          },
        },
      });

      store.delete('users');

      expect(store.inspect(), {});
    });
  });
}
