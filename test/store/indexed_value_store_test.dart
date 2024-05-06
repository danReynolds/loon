import 'package:flutter_test/flutter_test.dart';
import 'package:loon/loon.dart';

void main() {
  group('write', () {
    test('Writes the value to the given path', () {
      final store = IndexedValueStore<String>();

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
      final store = IndexedValueStore<String>();

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
    test('Removes the value at the given path from the store.', () {
      final store = IndexedValueStore<String>();

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

  group(
    'graft',
    () {
      test(
        'Moves the data from the other store to this store',
        () {
          final store = IndexedValueStore<String>();
          store.write('users__1', 'Dan');
          store.write('users__2', 'Sonja');
          store.write('users__1__messages__1', 'Hello');
          store.write('users__1__messages__2', 'How are you?');
          store.write('users__2__messages__1', 'Hey!');
          store.write('users__2__messages__2', "I'm good.");

          expect(store.inspect(), {
            "users": {
              "__values": {
                "1": "Dan",
                "2": "Sonja",
              },
              "1": {
                "messages": {
                  "__values": {
                    "1": "Hello",
                    "2": "How are you?",
                  },
                },
              },
              "2": {
                "messages": {
                  "__values": {
                    "1": "Hey!",
                    "2": "I'm good.",
                  }
                },
              },
            },
          });

          final store2 = IndexedValueStore<String>();
          store2.write('users__3', 'Chris');
          store2.write('users__4', 'Nik');
          store2.write('users__3__messages__1', 'Greetings');
          store2.write('users__3__messages__2', "What's up?");
          store2.write('users__1__messages__5', 'Salutations!');
          store2.write('users__2__messages__6', "Nothing special.");

          expect(store2.inspect(), {
            "users": {
              "__values": {
                "3": "Chris",
                "4": "Nik",
              },
              "1": {
                "messages": {
                  "__values": {
                    "5": "Salutations!",
                  },
                },
              },
              "2": {
                "messages": {
                  "__values": {
                    "6": "Nothing special.",
                  },
                },
              },
              "3": {
                "messages": {
                  "__values": {
                    "1": "Greetings",
                    "2": "What's up?",
                  },
                },
              },
            },
          });

          store.graft(store2);

          expect(store.inspect(), {
            "users": {
              "__values": {
                "1": "Dan",
                "2": "Sonja",
                "3": "Chris",
                "4": "Nik",
              },
              "1": {
                "messages": {
                  "__values": {
                    "1": "Hello",
                    "2": "How are you?",
                    "5": "Salutations!",
                  },
                },
              },
              "2": {
                "messages": {
                  "__values": {
                    "1": "Hey!",
                    "2": "I'm good.",
                    "6": "Nothing special.",
                  }
                },
              },
              "3": {
                "messages": {
                  "__values": {
                    "1": "Greetings",
                    "2": "What's up?",
                  }
                },
              },
            },
          });
          expect(store2.inspect(), {});
        },
      );

      test(
        'Moves the data under the given path from the other store to this store.',
        () {
          final store = IndexedValueStore<String>();
          store.write('users__1', 'Dan');
          store.write('users__2', 'Sonja');
          store.write('users__1__messages__1', 'Hello');
          store.write('users__1__messages__2', 'How are you?');
          store.write('users__2__messages__1', 'Hey!');
          store.write('users__2__messages__2', "I'm good.");

          expect(store.inspect(), {
            "users": {
              "__values": {
                "1": "Dan",
                "2": "Sonja",
              },
              "1": {
                "messages": {
                  "__values": {
                    "1": "Hello",
                    "2": "How are you?",
                  },
                },
              },
              "2": {
                "messages": {
                  "__values": {
                    "1": "Hey!",
                    "2": "I'm good.",
                  }
                },
              },
            },
          });

          final store2 = IndexedValueStore<String>();
          store2.write('users__1', 'Chris');
          store2.write('users__2', 'Nik');
          store2.write('users__3__messages__1', 'Greetings');
          store2.write('users__3__messages__2', "What's up?");
          store2.write('users__1__messages__5', 'Salutations!');
          store2.write('users__2__messages__6', "Nothing special.");

          expect(store2.inspect(), {
            "users": {
              "__values": {
                "1": "Chris",
                "2": "Nik",
              },
              "1": {
                "messages": {
                  "__values": {
                    "5": "Salutations!",
                  },
                },
              },
              "2": {
                "messages": {
                  "__values": {
                    "6": "Nothing special.",
                  },
                },
              },
              "3": {
                "messages": {
                  "__values": {
                    "1": "Greetings",
                    "2": "What's up?",
                  },
                },
              },
            },
          });

          store.graft(store2, 'users__1');

          expect(store.inspect(), {
            "users": {
              "__values": {
                "1": "Chris",
                "2": "Sonja",
              },
              "1": {
                "messages": {
                  "__values": {
                    "1": "Hello",
                    "2": "How are you?",
                    "5": "Salutations!",
                  },
                },
              },
              "2": {
                "messages": {
                  "__values": {
                    "1": "Hey!",
                    "2": "I'm good.",
                  }
                },
              },
            },
          });

          expect(store2.inspect(), {
            "users": {
              "__values": {
                "2": "Nik",
              },
              "2": {
                "messages": {
                  "__values": {
                    "6": "Nothing special.",
                  },
                },
              },
              "3": {
                "messages": {
                  "__values": {
                    "1": "Greetings",
                    "2": "What's up?",
                  },
                },
              },
            },
          });
        },
      );
    },
  );

  group('touch', () {
    test("Creates an empty node if necessary", () {
      final store = IndexedValueStore<String>();

      store.write('users__1__messages__1', 'Hey');
      store.touch('users__1');
      store.touch('users__2');

      expect(store.inspect(), {
        "users": {
          "1": {
            "messages": {
              "__values": {
                "1": "Hey",
              },
            },
          },
          "2": {},
        },
      });
    });
  });

  group('getNearest', () {
    test(
      'Returns the nearest value of a node in the path moving from the bottom up.',
      () {
        final store = IndexedValueStore<String>();

        store.write('users__1', 'Dan');
        store.write('users__1__posts__2', "You all mean so much to me");
        store.write('users__1__posts__2__reactions__3', 'Like');

        expect(store.getNearest('users__1__posts__2__reactions__3'), 'Like');

        store.delete('users__1__posts__2__reactions__3');

        expect(
          store.getNearest('users__1__posts__2__reactions__3'),
          "You all mean so much to me",
        );

        store.delete('users__1__posts__2');

        expect(store.getNearest('users__1__posts__2__reactions__3'), 'Dan');

        store.delete('users__1');

        expect(store.getNearest('users__1__posts__2__reactions__3'), null);
      },
    );
  });

  group('extractValues', () {
    test('Extracts all values in the store to a path/value map', () {
      final store = IndexedValueStore<String>();
      store.write('users__1', 'Dan');
      store.write('users__2', 'Sonja');
      store.write('users__1__messages__1', 'Hello');
      store.write('users__1__messages__2', 'How are you?');
      store.write('users__2__messages__1', 'Hey!');
      store.write('users__2__messages__2', "I'm good.");

      expect(store.extractValues(), {
        'users__1': 'Dan',
        'users__2': 'Sonja',
        'users__1__messages__1': 'Hello',
        'users__1__messages__2': 'How are you?',
        'users__2__messages__1': 'Hey!',
        'users__2__messages__2': "I'm good.",
      });
    });
  });
}
