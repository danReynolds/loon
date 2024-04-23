import 'package:flutter_test/flutter_test.dart';
import 'package:loon/loon.dart';

void main() {
  group('write', () {
    test('Writes the value to the given path', () {
      final store = ValueStore<String>();

      store.write('users', 'Collection value');
      store.write('users__1', 'Dan');
      store.write('users__2', 'Sonja');
      store.write('users__1__messages__2', 'Hey there!');

      expect(store.inspect(), {
        "__values": {
          "users": "Collection value",
        },
        "users": {
          "__values": {
            "1": "Dan",
            "2": "Sonja",
          },
          "1": {
            "messages": {
              "__values": {
                "2": "Hey there!",
              },
            },
          },
        }
      });
    });
  });

  group('get', () {
    test('Retrieves the value at the given path', () {
      final store = ValueStore<String>();

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
      final store = ValueStore<String>();

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
    test('Removes the path from the store.', () {
      final store = ValueStore<String>();

      store.write('users__1', 'Dan');
      store.write('users__2', 'Sonja');
      store.write('users__1__friends__1', 'Nik');

      expect(store.inspect(), {
        "users": {
          "__values": {
            "1": "Dan",
            "2": "Sonja",
          },
          "1": {
            "friends": {
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
