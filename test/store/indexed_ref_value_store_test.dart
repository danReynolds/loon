import 'package:flutter_test/flutter_test.dart';
import 'package:loon/loon.dart';

void main() {
  group('write', () {
    test('Writes the value to the given path and updates the ref count', () {
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

      store.write('users__1', 'Sonja');

      expect(store.inspect(), {
        "__refs": {
          "Collection value": 1,
        },
        "__values": {
          "users": "Collection value",
        },
        "users": {
          "__refs": {
            "Sonja": 2,
          },
          "__values": {
            "1": "Sonja",
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

  group('extractRefs', () {
    test(
      "Extracts the total ref count of all values in the store under the provided path",
      () {
        final store = IndexedRefValueStore<String>();

        store.write('users__1', 'Dan');
        store.write('users__2', 'Sonja');
        store.write('users__1__friends__1', 'Nik');
        store.write('users__1__friends__2', 'Dan');

        expect(store.extractRefs(), {
          "Dan": 2,
          "Sonja": 1,
          "Nik": 1,
        });

        expect(store.extractRefs('users__1'), {
          "Dan": 2,
          "Nik": 1,
        });

        store.delete('users__1__friends');

        expect(store.extractRefs(), {
          'Dan': 1,
          'Sonja': 1,
        });

        store.delete('users__1');

        expect(store.extractRefs(), {
          'Sonja': 1,
        });

        store.clear();

        expect(store.extractRefs(), {});
      },
    );
  });
}
