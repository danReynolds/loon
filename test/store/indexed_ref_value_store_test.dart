import 'package:flutter_test/flutter_test.dart';
import 'package:loon/loon.dart';

void main() {
  group(
    'write',
    () {
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

      test(
        'Should not increment the ref count when writing the same value multiple times',
        () {
          final store = IndexedRefValueStore<String>();

          store.write('users', 'Collection value');
          store.write('users__1', 'Dan');

          expect(
            store.inspect(),
            {
              "__refs": {
                "Collection value": 1,
              },
              "__values": {
                "users": "Collection value",
              },
              "users": {
                "__refs": {
                  "Dan": 1,
                },
                "__values": {
                  "1": 'Dan',
                },
              }
            },
          );

          store.write('users__1', 'Dan');

          expect(
            store.inspect(),
            {
              "__refs": {
                "Collection value": 1,
              },
              "__values": {
                "users": "Collection value",
              },
              "users": {
                "__refs": {
                  "Dan": 1,
                },
                "__values": {
                  "1": 'Dan',
                },
              }
            },
          );
        },
      );
    },
  );

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

        expect(store.extractRefs('users__1__friends'), {
          "Dan": 1,
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

  group('graft', () {
    test(
      "Merges the ref count from the source store into the destination store",
      () {
        final store = IndexedRefValueStore<String>();
        store.write('users__1', 'Dan');
        store.write('users__2', 'Chris');
        store.write('users__1__messages__1', 'Hello');

        final store2 = IndexedRefValueStore<String>();
        store2.write('users__3', 'Sonja');
        store2.write('users__1__messages__2', 'How are you');
        store2.write('users__3__messages__1', 'Hey there');

        expect(store.inspect(), {
          "users": {
            "__refs": {
              "Dan": 1,
              "Chris": 1,
            },
            "__values": {
              "1": "Dan",
              "2": "Chris",
            },
            "1": {
              "messages": {
                "__refs": {
                  "Hello": 1,
                },
                "__values": {
                  "1": "Hello",
                },
              }
            }
          }
        });

        expect(store2.inspect(), {
          "users": {
            "__refs": {
              "Sonja": 1,
            },
            "__values": {
              "3": "Sonja",
            },
            "1": {
              "messages": {
                "__refs": {
                  "How are you": 1,
                },
                "__values": {
                  "2": "How are you",
                },
              }
            },
            "3": {
              "messages": {
                "__refs": {
                  "Hey there": 1,
                },
                "__values": {
                  "1": "Hey there",
                }
              },
            }
          },
        });

        store.graft(store2, 'users__3');

        expect(store.inspect(), {
          "users": {
            "__refs": {
              "Dan": 1,
              "Chris": 1,
              "Sonja": 1,
            },
            "__values": {
              "1": "Dan",
              "2": "Chris",
              "3": "Sonja",
            },
            "1": {
              "messages": {
                "__refs": {
                  "Hello": 1,
                },
                "__values": {
                  "1": "Hello",
                },
              }
            },
            "3": {
              "messages": {
                "__refs": {
                  "Hey there": 1,
                },
                "__values": {
                  "1": "Hey there",
                },
              }
            }
          }
        });

        expect(store2.inspect(), {
          "users": {
            "1": {
              "messages": {
                "__refs": {
                  "How are you": 1,
                },
                "__values": {
                  "2": "How are you",
                },
              }
            },
          },
        });
      },
    );
  });
}
