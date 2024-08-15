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

  group('getChildValues', () {
    test('Retrieves all of the values of the children of the given path', () {
      final store = ValueStore<String>();

      store.write('users__1', 'Dan');
      store.write('users__2', 'Sonja');
      store.write('users__1__friends__1', 'Nik');

      expect(store.getChildValues('users__1'), null);
      expect(store.getChildValues('users__2'), null);
      expect(store.getChildValues('users'), {
        "1": "Dan",
        "2": "Sonja",
      });
      expect(store.getChildValues('users__1__friends'), {
        "1": "Nik",
      });
    });
  });

  group('hasValue', () {
    test('Returns whether a value exists at the given path', () {
      final store = ValueStore<String>();
      store.write('users__1', 'Test');

      expect(store.hasValue('users__1'), true);
      expect(store.hasValue('users__2'), false);
      expect(store.hasValue('users'), false);
    });
  });

  group('delete', () {
    group(
      "when recursive",
      () {
        test('Removes the value at the given path recursively from the store.',
            () {
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
      },
    );

    group('when not recursive', () {
      test("Should delete the value at the path and retain subpaths", () {
        final store = ValueStore<String>();

        store.write('users__1', 'Dan');
        store.write('users__2', 'Chris');
        store.write('users__1__posts__1', 'Hello');

        expect(store.inspect(), {
          "users": {
            "__values": {
              "1": "Dan",
              "2": "Chris",
            },
            "1": {
              "posts": {
                "__values": {
                  "1": "Hello",
                }
              }
            }
          },
        });

        store.delete('users__1', recursive: false);

        expect(store.inspect(), {
          "users": {
            "__values": {
              "2": "Chris",
            },
            "1": {
              "posts": {
                "__values": {
                  "1": "Hello",
                }
              }
            }
          },
        });

        store.delete('users', recursive: false);

        expect(store.inspect(), {
          "users": {
            "1": {
              "posts": {
                "__values": {
                  "1": "Hello",
                }
              }
            }
          },
        });

        // This is a no-op as the delete is not recursive and users__1 does not exist anymore.
        store.delete('users__1', recursive: false);

        expect(store.inspect(), {
          "users": {
            "1": {
              "posts": {
                "__values": {
                  "1": "Hello",
                }
              }
            }
          },
        });
      });
    });
  });

  group(
    'graft',
    () {
      test(
        'Moves the data from the other store to this store',
        () {
          final store = ValueStore<String>();
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

          final store2 = ValueStore<String>();
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
          final store = ValueStore<String>();
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

          final store2 = ValueStore<String>();
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

      test(
        "Deletes the source store's path if now empty",
        () {
          final store = ValueStore<String>();
          store.write('users__1', 'Dan');

          final store2 = ValueStore<String>();
          store2.write('users__2', 'Chris');
          store2.write('users__3', 'Sonja');

          store.graft(store2, 'users__2');

          expect(store.inspect(), {
            "users": {
              "__values": {
                "1": "Dan",
                "2": "Chris",
              },
            },
          });

          expect(store2.inspect(), {
            "users": {
              "__values": {
                "3": "Sonja",
              },
            },
          });

          // Grafting a deeper path that doesn't exist should not remove any parent path.
          store.graft(store2, 'users__3__messages__1');

          expect(store.inspect(), {
            "users": {
              "__values": {
                "1": "Dan",
                "2": "Chris",
              },
            },
          });

          expect(store2.inspect(), {
            "users": {
              "__values": {
                "3": "Sonja",
              },
            },
          });

          store.graft(store2, 'users__3');

          expect(store.inspect(), {
            "users": {
              "__values": {
                "1": "Dan",
                "2": "Chris",
                "3": "Sonja",
              },
            },
          });

          // Now that the last value under the `users` collection in the source collection
          // has been removed, it should delete the source's `users` collection path as well.
          expect(store2.inspect(), {});
        },
      );
    },
  );

  group('touch', () {
    test("Creates an empty node if necessary", () {
      final store = ValueStore<String>();

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
      'With no value, returns the nearest non-null node along the given path.',
      () {
        final store = ValueStore<String>();

        store.write(ValueStore.root, 'Root value');
        store.write('users__1', 'Dan');
        store.write('users__1__posts__2', "You all mean so much to me");
        store.write('users__1__posts__2__reactions__3', 'Like');

        expect(
          store.getNearest('users__1__posts__2__reactions__3'),
          ('users__1__posts__2__reactions__3', 'Like'),
        );

        store.delete('users__1__posts__2__reactions__3');

        expect(
          store.getNearest('users__1__posts__2__reactions__3'),
          ("users__1__posts__2", "You all mean so much to me"),
        );

        store.delete('users__1__posts__2');

        expect(
          store.getNearest('users__1__posts__2__reactions__3'),
          ('users__1', 'Dan'),
        );

        store.delete('users__1');

        expect(
          store.getNearest('users__1__posts__2__reactions__3'),
          (ValueStore.root, 'Root value'),
        );
      },
    );
  });

  group('getNearestMatch', () {
    test(
      "Returns the first matching value along the given path.",
      () {
        final store = ValueStore<String>();
        store.write('users__1', 'Dan');
        store.write('users__1__messages__1', 'Dan');
        store.write('users__1__messages__2', 'Sonja');

        expect(
          store.getNearestMatch('users__1__messages__1', 'Dan'),
          'users__1__messages__1',
        );
        expect(
          store.getNearestMatch('users__1__messages__2', 'Sonja'),
          'users__1__messages__2',
        );

        expect(
          store.getNearestMatch('users__1__messages__2__reactions__3', 'Sonja'),
          'users__1__messages__2',
        );
      },
    );
  });

  group('extract', () {
    test('Extracts all values in the store to a path/value map', () {
      final store = ValueStore<String>();
      store.write('users__1', 'Dan');
      store.write('users__2', 'Sonja');
      store.write('users__1__messages__1', 'Hello');
      store.write('users__1__messages__2', 'How are you?');
      store.write('users__2__messages__1', 'Hey!');
      store.write('users__2__messages__2', "I'm good.");

      expect(store.extract(), {
        'users__1': 'Dan',
        'users__2': 'Sonja',
        'users__1__messages__1': 'Hello',
        'users__1__messages__2': 'How are you?',
        'users__2__messages__1': 'Hey!',
        'users__2__messages__2': "I'm good.",
      });
    });

    test(
        'Extracts all values under the given path in the store to a path/value map',
        () {
      final store = ValueStore<String>();
      store.write('users__1', 'Dan');
      store.write('users__2', 'Sonja');
      store.write('users__1__messages__1', 'Hello');
      store.write('users__1__messages__2', 'How are you?');
      store.write('users__2__messages__1', 'Hey!');
      store.write('users__2__messages__2', "I'm good.");

      expect(store.extract('users__1'), {
        'users__1': 'Dan',
        'users__1__messages__1': 'Hello',
        'users__1__messages__2': 'How are you?',
      });
    });
  });

  group(
    'extractParentPath',
    () {
      test(
        'Returns all values along the given path',
        () {
          final store = ValueStore();

          store.write(ValueStore.root, 'Root value');
          store.write('users__1', 1);
          store.write('users__1__friends__2', 2);

          expect(store.extractParentPath('users__1'), {
            ValueStore.root: 'Root value',
            'users__1': 1,
          });
          expect(store.extractParentPath('users__1__friends__2'), {
            ValueStore.root: 'Root value',
            'users__1': 1,
            'users__1__friends__2': 2,
          });
          expect(store.extractParentPath('other_users'), {
            ValueStore.root: 'Root value',
          });
        },
      );
    },
  );

  group(
    'extractValues',
    () {
      test(
        'Extracts all unique values under the given path',
        () {
          final store = ValueStore();
          store.write('users__1', 'User 1');
          store.write('users__2', 'User 2');
          store.write('users__1__friends__1', 'Friend 1');
          store.write('users__1__friends__2', 'Friend 2');
          store.write('users__1__friends__3', 'Friend 2');

          expect(
            store.extractValues(),
            {
              'User 1',
              'User 2',
              'Friend 1',
              'Friend 2',
            },
          );

          expect(
            store.extractValues('users__1'),
            {
              'User 1',
              'Friend 1',
              'Friend 2',
            },
          );

          expect(
            store.extractValues('users__1__friends__1'),
            {'Friend 1'},
          );

          expect(store.extractValues('users__3'), <String>{});
        },
      );
    },
  );
}
