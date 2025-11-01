import 'package:encrypt/encrypt.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:loon/loon.dart';
import 'package:loon/persistor/data_store_encrypter.dart';

import '../../models/test_persistor.dart';
import '../../models/test_persistor_completer.dart';
import '../../models/test_user_model.dart';

typedef PersistorFactory<T> = T Function({
  void Function(Set<Document> batch)? onPersist,
  void Function(Set<StoreReference> refs)? onClear,
  void Function()? onClearAll,
  void Function(Json data)? onHydrate,
  void Function()? onSync,
  required PersistorSettings settings,
  required Duration persistenceThrottle,
  DataStoreEncrypter? encrypter,
});

/// Test runner for running the full suite of persistor tests against a persistor implementation
/// including [FilePersistor], [IndexedDBPersistor], etc.
void persistorTestRunner<T extends Persistor>({
  required PersistorFactory<T> factory,
  required Future<Map?> Function(
    T persistor,
    String storeName, {
    required bool encrypted,
  }) getStore,
  bool enableLogging = false,
}) {
  late T persistor;
  late TestPersistCompleter completer;

  // A custom encrypter is used in the test environment since FlutterSecureStorage
  // with not work in tests.
  final encrypter = DataStoreEncrypter(
    Encrypter(AES(Key.fromSecureRandom(32), mode: AESMode.cbc)),
  );

  Future<Map?> get(
    String store, {
    bool encrypted = false,
  }) async {
    return getStore(
      persistor,
      encrypted ? '$store.${DataStoreEncrypter.encryptedName}' : store,
      encrypted: encrypted,
    );
  }

  Future<bool> exists(
    String storeName, {
    bool encrypted = false,
  }) async {
    final result = await get(storeName, encrypted: encrypted);
    return result != null;
  }

  void configure({
    PersistorSettings settings = const PersistorSettings(),
  }) {
    completer = TestPersistCompleter();
    persistor = factory(
      persistenceThrottle: const Duration(milliseconds: 1),
      encrypter: encrypter,
      settings: settings,
      onPersist: (docs) {
        completer.persistComplete();
      },
      onHydrate: (refs) {
        completer.hydrateComplete();
      },
      onClear: (refs) {
        completer.clearComplete();
      },
      onClearAll: () {
        completer.clearAllComplete();
      },
      onSync: () {
        completer.syncComplete();
      },
    );

    Loon.configure(persistor: persistor, enableLogging: enableLogging);
  }

  group('Persistor Test Runner', () {
    setUp(() async {
      configure();
    });

    tearDown(() async {
      await Loon.clearAll();
    });

    group(
      'persist',
      () {
        test(
          'Persists new documents in the default data store by default',
          () async {
            final userCollection = Loon.collection<TestUserModel>(
              'users',
              fromJson: TestUserModel.fromJson,
              toJson: (user) => user.toJson(),
            );

            final userDoc = userCollection.doc('1');
            final userDoc2 = userCollection.doc('2');

            final user = TestUserModel('User 1');
            final user2 = TestUserModel('User 2');

            userDoc.create(user);
            userDoc2.create(user2);
            userDoc2
                .subcollection(
                  'friends',
                  fromJson: TestUserModel.fromJson,
                  toJson: (user) => user.toJson(),
                )
                .doc('1')
                .create(user);

            await completer.onSync;

            expect(
              await get('__store__'),
              {
                "": {
                  "users": {
                    "__values": {
                      "1": {'name': 'User 1'},
                      "2": {'name': 'User 2'},
                    },
                    "2": {
                      "friends": {
                        "__values": {
                          "1": {'name': 'User 1'},
                        }
                      }
                    }
                  }
                }
              },
            );

            // The resolver is not necessary for data only persisted in the root data store.
            expect(await exists('__resolver__'), false);
          },
        );

        test(
          'Persists updates to documents',
          () async {
            final userCollection = Loon.collection(
              'users',
              fromJson: TestUserModel.fromJson,
              toJson: (user) => user.toJson(),
            );

            userCollection.doc('1').create(TestUserModel('User 1'));
            userCollection.doc('2').create(TestUserModel('User 2'));

            await completer.onSync;

            userCollection.doc('2').update(TestUserModel('User 2 updated'));

            await completer.onSync;

            expect(
              await get('__store__'),
              {
                "": {
                  "users": {
                    "__values": {
                      "1": {'name': 'User 1'},
                      "2": {'name': 'User 2 updated'},
                    }
                  }
                }
              },
            );
          },
        );

        test(
          'Persists serializable document data without a serializer',
          () async {
            final userCollection = Loon.collection('users');

            userCollection.doc('1').create(1);
            userCollection.doc('2').create('2');
            userCollection.doc('3').create(true);
            userCollection.doc('4').create({
              "name": 1,
            });

            await completer.onSync;

            expect(
              await get('__store__'),
              {
                "": {
                  "users": {
                    "__values": {
                      "1": 1,
                      "2": '2',
                      "3": true,
                      "4": {
                        "name": 1,
                      }
                    }
                  }
                }
              },
            );
          },
        );

        test(
          'Removes deleted documents',
          () async {
            final userCollection = Loon.collection(
              'users',
              fromJson: TestUserModel.fromJson,
              toJson: (user) => user.toJson(),
            );

            userCollection.doc('1').create(TestUserModel('User 1'));
            userCollection.doc('2').create(TestUserModel('User 2'));

            await completer.onSync;

            expect(
              await get('__store__'),
              {
                "": {
                  "users": {
                    "__values": {
                      "1": {"name": "User 1"},
                      "2": {"name": "User 2"}
                    },
                  }
                }
              },
            );

            userCollection.doc('2').delete();

            await completer.onSync;

            expect(
              await get('__store__'),
              {
                "": {
                  "users": {
                    "__values": {
                      "1": {"name": "User 1"}
                    },
                  }
                }
              },
            );
          },
        );

        test(
          'Deletes empty data stores',
          () async {
            final userCollection = Loon.collection(
              'users',
              fromJson: TestUserModel.fromJson,
              toJson: (user) => user.toJson(),
            );

            userCollection.doc('1').create(TestUserModel('User 1'));
            userCollection.doc('2').create(TestUserModel('User 2'));

            await completer.onSync;

            expect(await exists('__store__'), true);

            // If all documents in a data store are deleted, the store itself should be deleted.
            userCollection.doc('1').delete();
            userCollection.doc('2').delete();

            await completer.onSync;

            expect(await exists('__store__'), false);
          },
        );

        test(
          'Persists documents with a value key',
          () async {
            final userCollection = Loon.collection<TestUserModel>(
              'users',
              fromJson: TestUserModel.fromJson,
              toJson: (user) => user.toJson(),
            );

            final userDoc = userCollection.doc('1');
            final userDoc2 = userCollection.doc('2');

            final user = TestUserModel('User 1');
            final user2 = TestUserModel('User 2');

            final friend1 = TestUserModel('Friend 1');
            final friend2 = TestUserModel('Friend 2');

            userDoc.create(user);
            userDoc2.create(user2);
            final friendsCollection = userDoc2.subcollection(
              'friends',
              fromJson: TestUserModel.fromJson,
              toJson: (friend) => friend.toJson(),
              // Aggregate all the `friends` subcollections of users into the `friends` data store.
              persistorSettings:
                  PersistorSettings(key: Persistor.key('friends')),
            );
            friendsCollection.doc('1').create(friend1);
            friendsCollection.doc('2').create(friend2);

            await completer.onSync;

            expect(
              await get('__store__'),
              {
                ValueStore.root: {
                  "users": {
                    "__values": {
                      "1": {'name': 'User 1'},
                      "2": {'name': 'User 2'},
                    },
                  }
                },
              },
            );

            expect(
              await get('friends'),
              {
                "users__2__friends": {
                  "users": {
                    "2": {
                      "friends": {
                        "__values": {
                          "1": {'name': 'Friend 1'},
                          "2": {'name': 'Friend 2'},
                        }
                      }
                    }
                  }
                }
              },
            );

            expect(
              await get('__resolver__'),
              {
                "__refs": {
                  "friends": 1,
                  Persistor.defaultKey.value: 1,
                },
                "__values": {
                  ValueStore.root: Persistor.defaultKey.value,
                },
                "users": {
                  "__refs": {
                    "friends": 1,
                  },
                  "2": {
                    "__refs": {
                      "friends": 1,
                    },
                    "__values": {
                      "friends": "friends",
                    },
                  }
                }
              },
            );

            friendsCollection.doc('1').delete();

            await completer.onSync;

            expect(
              await get('friends'),
              {
                "users__2__friends": {
                  "users": {
                    "2": {
                      "friends": {
                        "__values": {
                          "2": {'name': 'Friend 2'},
                        }
                      }
                    }
                  }
                }
              },
            );

            expect(
              await get('__resolver__'),
              {
                "__refs": {
                  "friends": 1,
                  Persistor.defaultKey.value: 1,
                },
                "__values": {
                  ValueStore.root: Persistor.defaultKey.value,
                },
                "users": {
                  "__refs": {
                    "friends": 1,
                  },
                  "2": {
                    "__refs": {
                      "friends": 1,
                    },
                    "__values": {
                      "friends": "friends",
                    },
                  }
                }
              },
            );

            friendsCollection.delete();

            await completer.onSync;

            expect(await exists('friends'), false);

            expect(
              await get('__resolver__'),
              {
                "__refs": {
                  Persistor.defaultKey.value: 1,
                },
                "__values": {
                  ValueStore.root: Persistor.defaultKey.value,
                },
              },
            );
          },
        );

        test(
          'Persists documents with a key builder',
          () async {
            final userCollection = Loon.collection<TestUserModel>(
              'users',
              fromJson: TestUserModel.fromJson,
              toJson: (user) => user.toJson(),
              persistorSettings: PersistorSettings(
                key: Persistor.keyBuilder<TestUserModel>((snap) {
                  if (snap.id == '1') {
                    return 'users';
                  }
                  return 'other_users';
                }),
              ),
            );

            userCollection.doc('1').create(TestUserModel('User 1'));
            userCollection.doc('2').create(TestUserModel('User 2'));

            await completer.onSync;

            expect(
              await get('users'),
              {
                "users__1": {
                  "users": {
                    "__values": {
                      "1": {'name': 'User 1'},
                    },
                  }
                },
              },
            );

            expect(
              await get('other_users'),
              {
                "users__2": {
                  "users": {
                    "__values": {
                      "2": {'name': 'User 2'},
                    },
                  }
                }
              },
            );

            expect(
              await get('__resolver__'),
              {
                "__refs": {
                  "users": 1,
                  "other_users": 1,
                  Persistor.defaultKey.value: 1,
                },
                "__values": {
                  ValueStore.root: Persistor.defaultKey.value,
                },
                "users": {
                  "__refs": {
                    "users": 1,
                    "other_users": 1,
                  },
                  "__values": {
                    "1": "users",
                    "2": "other_users",
                  }
                }
              },
            );

            userCollection.doc('1').delete();

            await completer.onSync;

            expect(await exists('users'), false);
            expect(
              await get('other_users'),
              {
                "users__2": {
                  "users": {
                    "__values": {
                      "2": {'name': 'User 2'},
                    },
                  }
                }
              },
            );

            expect(
              await get('__resolver__'),
              {
                "__refs": {
                  "other_users": 1,
                  Persistor.defaultKey.value: 1,
                },
                "__values": {
                  ValueStore.root: Persistor.defaultKey.value,
                },
                "users": {
                  "__refs": {
                    "other_users": 1,
                  },
                  "__values": {
                    "2": "other_users",
                  }
                }
              },
            );

            userCollection.delete();

            await completer.onSync;

            expect(await exists('other_users'), false);

            expect(
              await get('__resolver__'),
              {
                "__refs": {
                  Persistor.defaultKey.value: 1,
                },
                "__values": {
                  ValueStore.root: Persistor.defaultKey.value,
                },
              },
            );
          },
        );

        test(
          'Subcollections inherit a parent value key',
          () async {
            final userCollection = Loon.collection<TestUserModel>(
              'users',
              fromJson: TestUserModel.fromJson,
              toJson: (user) => user.toJson(),
              persistorSettings: PersistorSettings(
                key: Persistor.key('users'),
              ),
            );

            final userDoc = userCollection.doc('1');
            final userDoc2 = userCollection.doc('2');

            final user = TestUserModel('User 1');
            final user2 = TestUserModel('User 2');

            final friend1 = TestUserModel('Friend 1');
            final friend2 = TestUserModel('Friend 2');

            userDoc.create(user);
            userDoc2.create(user2);
            final friendsCollection = userDoc2.subcollection(
              'friends',
              fromJson: TestUserModel.fromJson,
              toJson: (friend) => friend.toJson(),
            );
            friendsCollection.doc('1').create(friend1);
            friendsCollection.doc('2').create(friend2);

            await completer.onSync;

            // All data is stored in the users.json
            expect(await exists('__store__'), false);

            expect(
              await get('users'),
              {
                "users": {
                  "users": {
                    "__values": {
                      "1": {'name': 'User 1'},
                      "2": {'name': 'User 2'},
                    },
                    "2": {
                      "friends": {
                        "__values": {
                          "1": {'name': 'Friend 1'},
                          "2": {'name': 'Friend 2'},
                        }
                      }
                    }
                  }
                }
              },
            );

            expect(
              await get('__resolver__'),
              {
                "__refs": {
                  "users": 1,
                  Persistor.defaultKey.value: 1,
                },
                "__values": {
                  ValueStore.root: Persistor.defaultKey.value,
                  "users": "users",
                },
              },
            );
          },
        );

        test(
          'Subcollections can override a parent value key',
          () async {
            final userCollection = Loon.collection<TestUserModel>(
              'users',
              fromJson: TestUserModel.fromJson,
              toJson: (user) => user.toJson(),
              persistorSettings: PersistorSettings(
                key: Persistor.key('users'),
              ),
            );

            final userDoc = userCollection.doc('1');
            final userDoc2 = userCollection.doc('2');

            final user = TestUserModel('User 1');
            final user2 = TestUserModel('User 2');

            final friend1 = TestUserModel('Friend 1');
            final friend2 = TestUserModel('Friend 2');

            userDoc.create(user);
            userDoc2.create(user2);
            final friendsCollection = userDoc2.subcollection(
              'friends',
              fromJson: TestUserModel.fromJson,
              toJson: (friend) => friend.toJson(),
              persistorSettings: PersistorSettings(
                key: Persistor.key('friends'),
              ),
            );
            friendsCollection.doc('1').create(friend1);
            friendsCollection.doc('2').create(friend2);

            await completer.onSync;

            expect(
              await get('users'),
              {
                "users": {
                  "users": {
                    "__values": {
                      "1": {'name': 'User 1'},
                      "2": {'name': 'User 2'},
                    },
                  }
                }
              },
            );

            expect(
              await get('friends'),
              {
                "users__2__friends": {
                  "users": {
                    "2": {
                      "friends": {
                        "__values": {
                          "1": {'name': 'Friend 1'},
                          "2": {'name': 'Friend 2'},
                        }
                      }
                    }
                  }
                }
              },
            );

            // Since the friends collection under users__2 specifies a "friends" key,
            // this overrides the parent path's "users" key on the users collection and
            // therefore resolves the friends documents to the "friends" data store.
            expect(
              await get('__resolver__'),
              {
                "__refs": {
                  "users": 1,
                  "friends": 1,
                  Persistor.defaultKey.value: 1,
                },
                "__values": {
                  ValueStore.root: Persistor.defaultKey.value,
                  "users": "users",
                },
                "users": {
                  "__refs": {
                    "friends": 1,
                  },
                  "2": {
                    "__refs": {
                      "friends": 1,
                    },
                    "__values": {
                      "friends": "friends",
                    }
                  }
                },
              },
            );
          },
        );

        test(
          'Subcollections inherit a parent key builder',
          () async {
            final userCollection = Loon.collection<TestUserModel>(
              'users',
              fromJson: TestUserModel.fromJson,
              toJson: (user) => user.toJson(),
              persistorSettings: PersistorSettings(
                key: Persistor.keyBuilder<TestUserModel>((snap) {
                  return 'users_${snap.id}';
                }),
              ),
            );

            final userDoc = userCollection.doc('1');
            final userDoc2 = userCollection.doc('2');

            final user = TestUserModel('User 1');
            final user2 = TestUserModel('User 2');

            final friend1 = TestUserModel('Friend 1');
            final friend2 = TestUserModel('Friend 2');

            userDoc.create(user);
            userDoc2.create(user2);
            final friendsCollection = userDoc.subcollection(
              'friends',
              fromJson: TestUserModel.fromJson,
              toJson: (friend) => friend.toJson(),
            );
            final friends2Collection = userDoc2.subcollection(
              'friends',
              fromJson: TestUserModel.fromJson,
              toJson: (friend) => friend.toJson(),
            );
            friendsCollection.doc('1').create(friend1);
            friends2Collection.doc('2').create(friend2);

            await completer.onSync;

            expect(
              await get('users_1'),
              {
                "users__1": {
                  "users": {
                    "__values": {
                      "1": {'name': 'User 1'},
                    },
                    "1": {
                      "friends": {
                        "__values": {
                          "1": {'name': 'Friend 1'},
                        }
                      }
                    }
                  }
                }
              },
            );

            expect(
              await get('users_2'),
              {
                "users__2": {
                  "users": {
                    "__values": {
                      "2": {'name': 'User 2'},
                    },
                    "2": {
                      "friends": {
                        "__values": {
                          "2": {'name': 'Friend 2'},
                        }
                      }
                    }
                  }
                }
              },
            );

            expect(
              await get('__resolver__'),
              {
                "__refs": {
                  Persistor.defaultKey.value: 1,
                  "users_1": 1,
                  "users_2": 1,
                },
                "__values": {
                  ValueStore.root: Persistor.defaultKey.value,
                },
                "users": {
                  "__refs": {
                    "users_1": 1,
                    "users_2": 1,
                  },
                  "__values": {
                    "1": "users_1",
                    "2": "users_2",
                  }
                }
              },
            );
          },
        );

        test(
          'Subcollections can override a parent key builder',
          () async {
            final userCollection = Loon.collection<TestUserModel>(
              'users',
              fromJson: TestUserModel.fromJson,
              toJson: (user) => user.toJson(),
              persistorSettings: PersistorSettings(
                key: Persistor.keyBuilder<TestUserModel>((snap) {
                  return 'users_${snap.id}';
                }),
              ),
            );

            final userDoc = userCollection.doc('1');
            final userDoc2 = userCollection.doc('2');

            final user = TestUserModel('User 1');
            final user2 = TestUserModel('User 2');

            final friend1 = TestUserModel('Friend 1');
            final friend2 = TestUserModel('Friend 2');

            userDoc.create(user);
            userDoc2.create(user2);
            final friendsCollection = userDoc.subcollection(
              'friends',
              fromJson: TestUserModel.fromJson,
              toJson: (friend) => friend.toJson(),
              persistorSettings: PersistorSettings(
                key: Persistor.keyBuilder<TestUserModel>((snap) {
                  return 'friends_${snap.id}';
                }),
              ),
            );
            final friends2Collection = userDoc2.subcollection(
              'friends',
              fromJson: TestUserModel.fromJson,
              toJson: (friend) => friend.toJson(),
              persistorSettings: PersistorSettings(
                key: Persistor.keyBuilder<TestUserModel>((snap) {
                  return 'friends_${snap.id}';
                }),
              ),
            );
            friendsCollection.doc('1').create(friend1);
            friends2Collection.doc('2').create(friend2);

            await completer.onSync;

            expect(
              await get('users_1'),
              {
                "users__1": {
                  "users": {
                    "__values": {
                      "1": {'name': 'User 1'},
                    },
                  }
                }
              },
            );
            expect(
              await get('friends_1'),
              {
                "users__1__friends__1": {
                  "users": {
                    "1": {
                      "friends": {
                        "__values": {
                          "1": {'name': 'Friend 1'},
                        }
                      }
                    }
                  }
                }
              },
            );

            expect(
              await get('users_2'),
              {
                "users__2": {
                  "users": {
                    "__values": {
                      "2": {'name': 'User 2'},
                    },
                  }
                }
              },
            );
            expect(
              await get('friends_2'),
              {
                "users__2__friends__2": {
                  "users": {
                    "2": {
                      "friends": {
                        "__values": {
                          "2": {'name': 'Friend 2'},
                        }
                      }
                    }
                  }
                }
              },
            );

            expect(
              await get('__resolver__'),
              {
                "__refs": {
                  "users_1": 1,
                  "users_2": 1,
                  "friends_1": 1,
                  "friends_2": 1,
                  Persistor.defaultKey.value: 1,
                },
                "__values": {
                  ValueStore.root: Persistor.defaultKey.value,
                },
                "users": {
                  "__refs": {
                    "users_1": 1,
                    "users_2": 1,
                    "friends_1": 1,
                    "friends_2": 1,
                  },
                  "__values": {
                    "1": "users_1",
                    "2": "users_2",
                  },
                  "1": {
                    "__refs": {
                      "friends_1": 1,
                    },
                    "friends": {
                      "__refs": {
                        "friends_1": 1,
                      },
                      "__values": {
                        "1": "friends_1",
                      }
                    }
                  },
                  "2": {
                    "__refs": {
                      "friends_2": 1,
                    },
                    "friends": {
                      "__refs": {
                        "friends_2": 1,
                      },
                      "__values": {
                        "2": "friends_2",
                      }
                    }
                  },
                }
              },
            );
          },
        );

        test(
          'Subcollections can specify to be persisted in the default store.',
          () async {
            final userCollection = Loon.collection<TestUserModel>(
              'users',
              fromJson: TestUserModel.fromJson,
              toJson: (user) => user.toJson(),
              persistorSettings: PersistorSettings(
                key: Persistor.key('users'),
              ),
            );

            final userDoc = userCollection.doc('1');
            final userDoc2 = userCollection.doc('2');

            final user = TestUserModel('User 1');
            final user2 = TestUserModel('User 2');

            final friend1 = TestUserModel('Friend 1');
            final friend2 = TestUserModel('Friend 2');

            userDoc.create(user);
            userDoc2.create(user2);
            final friendsCollection = userDoc2.subcollection(
              'friends',
              fromJson: TestUserModel.fromJson,
              toJson: (friend) => friend.toJson(),
              persistorSettings: PersistorSettings(key: Persistor.defaultKey),
            );
            friendsCollection.doc('1').create(friend1);
            friendsCollection.doc('2').create(friend2);

            await completer.onSync;

            expect(
              await get('users'),
              {
                "users": {
                  "users": {
                    "__values": {
                      "1": {'name': 'User 1'},
                      "2": {'name': 'User 2'},
                    },
                  }
                }
              },
            );

            expect(
              await get('__store__'),
              {
                "users__2__friends": {
                  "users": {
                    "2": {
                      "friends": {
                        "__values": {
                          "1": {'name': 'Friend 1'},
                          "2": {'name': 'Friend 2'},
                        }
                      }
                    }
                  }
                }
              },
            );

            // Since the friends collection under users__2 specifies a "friends" key,
            // this overrides the parent path's "users" key on the users collection and
            // therefore resolves the friends documents to the "friends" data store.
            expect(
              await get('__resolver__'),
              {
                "__refs": {
                  "users": 1,
                  Persistor.defaultKey.value: 2,
                },
                "__values": {
                  ValueStore.root: Persistor.defaultKey.value,
                  "users": "users",
                },
                "users": {
                  "__refs": {
                    Persistor.defaultKey.value: 1,
                  },
                  "2": {
                    "__refs": {
                      Persistor.defaultKey.value: 1,
                    },
                    "__values": {
                      "friends": Persistor.defaultKey.value,
                    }
                  }
                },
              },
            );
          },
        );

        // The following group of tests cover the scenarios where a persistence key for a path changes:
        // 1. null -> value key
        // 2. null -> builder key
        // 3. value key -> null
        // 4. builder key -> null
        // 5. value key -> updated value key
        // 6. builder key -> updated builder key
        // 7. value key -> builder key
        // 8. builder key -> value key
        group(
          'Persistence key changes',
          () {
            group(
              '1. null -> value key',
              () {
                test(
                  'Moves all documents and their subcollections in the default store to the store specified by the value key',
                  () async {
                    final usersCollection = Loon.collection<TestUserModel>(
                      'users',
                      fromJson: TestUserModel.fromJson,
                      toJson: (user) => user.toJson(),
                    );

                    final updatedUsersCollection =
                        Loon.collection<TestUserModel>(
                      'users',
                      fromJson: TestUserModel.fromJson,
                      toJson: (user) => user.toJson(),
                      persistorSettings: PersistorSettings(
                        key: Persistor.key('other_users'),
                      ),
                    );

                    usersCollection.doc('1').create(TestUserModel('User 1'));
                    usersCollection.doc('2').create(TestUserModel('User 2'));
                    usersCollection
                        .doc('1')
                        .subcollection(
                          'friends',
                          fromJson: TestUserModel.fromJson,
                          toJson: (user) => user.toJson(),
                        )
                        .doc('1')
                        .create(TestUserModel('Friend 1'));

                    await completer.onSync;

                    expect(
                      await get('__store__'),
                      {
                        ValueStore.root: {
                          "users": {
                            "__values": {
                              "1": {"name": "User 1"},
                              "2": {"name": "User 2"},
                            },
                            "1": {
                              "friends": {
                                "__values": {
                                  "1": {"name": "Friend 1"},
                                }
                              }
                            }
                          }
                        }
                      },
                    );

                    expect(await exists('__resolver__'), false);

                    updatedUsersCollection
                        .doc('1')
                        .update(TestUserModel('User 1 updated'));

                    await completer.onSync;

                    expect(await exists('__store__'), false);

                    expect(
                      await get('other_users'),
                      {
                        "users": {
                          "users": {
                            "__values": {
                              "1": {"name": "User 1 updated"},
                              "2": {"name": "User 2"},
                            },
                            "1": {
                              "friends": {
                                "__values": {
                                  "1": {"name": "Friend 1"},
                                }
                              }
                            }
                          }
                        }
                      },
                    );

                    expect(
                      await get('__resolver__'),
                      {
                        "__refs": {
                          "other_users": 1,
                          Persistor.defaultKey.value: 1,
                        },
                        "__values": {
                          "users": "other_users",
                          ValueStore.root: Persistor.defaultKey.value,
                        },
                      },
                    );
                  },
                );
              },
            );

            group(
              '2. null -> builder key',
              () {
                test(
                  'Moves the document and its subcollections in the default store to the store specified by its builder key',
                  () async {
                    final usersCollection = Loon.collection<TestUserModel>(
                      'users',
                      fromJson: TestUserModel.fromJson,
                      toJson: (user) => user.toJson(),
                    );

                    final updatedUsersCollection =
                        Loon.collection<TestUserModel>(
                      'users',
                      fromJson: TestUserModel.fromJson,
                      toJson: (user) => user.toJson(),
                      persistorSettings: PersistorSettings(
                        key: Persistor.keyBuilder(
                          (snap) => 'users_${snap.id}',
                        ),
                      ),
                    );

                    usersCollection.doc('1').create(TestUserModel('User 1'));
                    usersCollection.doc('2').create(TestUserModel('User 2'));
                    usersCollection
                        .doc('1')
                        .subcollection(
                          'friends',
                          fromJson: TestUserModel.fromJson,
                          toJson: (user) => user.toJson(),
                        )
                        .doc('1')
                        .create(TestUserModel('Friend 1'));

                    await completer.onSync;

                    expect(
                      await get('__store__'),
                      {
                        ValueStore.root: {
                          "users": {
                            "__values": {
                              "1": {"name": "User 1"},
                              "2": {"name": "User 2"},
                            },
                            "1": {
                              "friends": {
                                "__values": {
                                  "1": {"name": "Friend 1"},
                                }
                              }
                            }
                          }
                        }
                      },
                    );

                    expect(await exists('__resolver__'), false);

                    updatedUsersCollection
                        .doc('1')
                        .update(TestUserModel('User 1 updated'));

                    await completer.onSync;

                    expect(
                      await get('__store__'),
                      {
                        ValueStore.root: {
                          "users": {
                            "__values": {
                              "2": {"name": "User 2"},
                            },
                          }
                        }
                      },
                    );

                    expect(
                      await get('users_1'),
                      {
                        "users__1": {
                          "users": {
                            "__values": {
                              "1": {"name": "User 1 updated"},
                            },
                            "1": {
                              "friends": {
                                "__values": {
                                  "1": {"name": "Friend 1"},
                                }
                              }
                            }
                          }
                        }
                      },
                    );

                    expect(
                      await get('__resolver__'),
                      {
                        "__refs": {
                          Persistor.defaultKey.value: 1,
                          "users_1": 1,
                        },
                        "__values": {
                          ValueStore.root: Persistor.defaultKey.value,
                        },
                        "users": {
                          "__refs": {
                            "users_1": 1,
                          },
                          "__values": {
                            "1": "users_1",
                          }
                        }
                      },
                    );
                  },
                );
              },
            );

            group(
              '3. value key -> null',
              () {
                test(
                  'Moves the collection and its subcollections in the previous document store to the default store',
                  () async {
                    final valueKeyUsersCollection =
                        Loon.collection<TestUserModel>(
                      'users',
                      fromJson: TestUserModel.fromJson,
                      toJson: (user) => user.toJson(),
                      persistorSettings: PersistorSettings(
                        key: Persistor.key('users'),
                      ),
                    );
                    final usersCollection = Loon.collection<TestUserModel>(
                      'users',
                      fromJson: TestUserModel.fromJson,
                      toJson: (user) => user.toJson(),
                    );

                    valueKeyUsersCollection
                        .doc('1')
                        .create(TestUserModel('User 1'));
                    valueKeyUsersCollection
                        .doc('2')
                        .create(TestUserModel('User 2'));
                    valueKeyUsersCollection
                        .doc('1')
                        .subcollection(
                          'friends',
                          fromJson: TestUserModel.fromJson,
                          toJson: (user) => user.toJson(),
                        )
                        .doc('1')
                        .create(TestUserModel('Friend 1'));

                    await completer.onSync;

                    expect(
                      await get('users'),
                      {
                        "users": {
                          "users": {
                            "__values": {
                              "1": {"name": "User 1"},
                              "2": {"name": "User 2"},
                            },
                            "1": {
                              "friends": {
                                "__values": {
                                  "1": {"name": "Friend 1"},
                                }
                              }
                            }
                          }
                        }
                      },
                    );

                    expect(
                      await get('__resolver__'),
                      {
                        "__refs": {
                          Persistor.defaultKey.value: 1,
                          "users": 1,
                        },
                        "__values": {
                          ValueStore.root: Persistor.defaultKey.value,
                          "users": "users",
                        },
                      },
                    );

                    usersCollection
                        .doc('1')
                        .update(TestUserModel('User 1 updated'));

                    await completer.onSync;

                    expect(
                      await get('__store__'),
                      {
                        ValueStore.root: {
                          "users": {
                            "__values": {
                              "1": {"name": "User 1 updated"},
                              "2": {"name": "User 2"},
                            },
                            "1": {
                              "friends": {
                                "__values": {
                                  "1": {"name": "Friend 1"},
                                }
                              }
                            }
                          }
                        }
                      },
                    );

                    expect(await exists('users'), false);

                    expect(
                      await get('__resolver__'),
                      {
                        "__refs": {
                          Persistor.defaultKey.value: 1,
                        },
                        "__values": {
                          ValueStore.root: Persistor.defaultKey.value,
                        },
                      },
                    );
                  },
                );
              },
            );

            group(
              '4. builder key -> null',
              () {
                test(
                  'Moves the document and its subcollections in the previous document store to the default store',
                  () async {
                    final keyBuilderUsersCollection =
                        Loon.collection<TestUserModel>(
                      'users',
                      fromJson: TestUserModel.fromJson,
                      toJson: (user) => user.toJson(),
                      persistorSettings: PersistorSettings(
                        key: Persistor.keyBuilder(
                          (snap) => "users_${snap.id}",
                        ),
                      ),
                    );
                    final usersCollection = Loon.collection<TestUserModel>(
                      'users',
                      fromJson: TestUserModel.fromJson,
                      toJson: (user) => user.toJson(),
                    );

                    keyBuilderUsersCollection
                        .doc('1')
                        .create(TestUserModel('User 1'));
                    keyBuilderUsersCollection
                        .doc('2')
                        .create(TestUserModel('User 2'));
                    keyBuilderUsersCollection
                        .doc('1')
                        .subcollection(
                          'friends',
                          fromJson: TestUserModel.fromJson,
                          toJson: (user) => user.toJson(),
                        )
                        .doc('1')
                        .create(TestUserModel('Friend 1'));

                    await completer.onSync;

                    expect(
                      await get('users_1'),
                      {
                        "users__1": {
                          "users": {
                            "__values": {
                              "1": {"name": "User 1"},
                            },
                            "1": {
                              "friends": {
                                "__values": {
                                  "1": {"name": "Friend 1"},
                                }
                              }
                            }
                          }
                        }
                      },
                    );

                    expect(
                      await get('users_2'),
                      {
                        "users__2": {
                          "users": {
                            "__values": {
                              "2": {"name": "User 2"},
                            },
                          }
                        }
                      },
                    );

                    expect(
                      await get('__resolver__'),
                      {
                        "__refs": {
                          Persistor.defaultKey.value: 1,
                          "users_1": 1,
                          "users_2": 1,
                        },
                        "__values": {
                          ValueStore.root: Persistor.defaultKey.value,
                        },
                        "users": {
                          "__refs": {
                            "users_1": 1,
                            "users_2": 1,
                          },
                          "__values": {
                            "1": "users_1",
                            "2": "users_2",
                          }
                        }
                      },
                    );

                    usersCollection
                        .doc('1')
                        .update(TestUserModel('User 1 updated'));

                    await completer.onSync;

                    expect(
                      await get('__store__'),
                      {
                        ValueStore.root: {
                          "users": {
                            "__values": {
                              "1": {"name": "User 1 updated"},
                            },
                            "1": {
                              "friends": {
                                "__values": {
                                  "1": {"name": "Friend 1"},
                                }
                              }
                            }
                          }
                        }
                      },
                    );

                    expect(await exists('users_1'), false);

                    expect(
                      await get('users_2'),
                      {
                        "users__2": {
                          "users": {
                            "__values": {
                              "2": {"name": "User 2"},
                            },
                          }
                        }
                      },
                    );

                    expect(
                      await get('__resolver__'),
                      {
                        "__refs": {
                          Persistor.defaultKey.value: 1,
                          "users_2": 1,
                        },
                        "__values": {
                          ValueStore.root: Persistor.defaultKey.value,
                        },
                        "users": {
                          "__refs": {
                            "users_2": 1,
                          },
                          "__values": {
                            "2": "users_2",
                          }
                        }
                      },
                    );
                  },
                );
              },
            );

            group(
              '5. value key -> updated value key',
              () {
                test(
                  'Moves the collection and its subcollections from the previous store to the store specified by its updated value key',
                  () async {
                    final userCollection = Loon.collection<TestUserModel>(
                      'users',
                      fromJson: TestUserModel.fromJson,
                      toJson: (user) => user.toJson(),
                      persistorSettings: PersistorSettings(
                        key: Persistor.key('users'),
                      ),
                    );
                    final updatedUsersCollection =
                        Loon.collection<TestUserModel>(
                      'users',
                      fromJson: TestUserModel.fromJson,
                      toJson: (user) => user.toJson(),
                      persistorSettings: PersistorSettings(
                        key: Persistor.key('updated_users'),
                      ),
                    );

                    final userDoc = userCollection.doc('1');
                    final userDoc2 = userCollection.doc('2');

                    userDoc.create(TestUserModel('User 1'));
                    userDoc2.create(TestUserModel('User 2'));

                    userDoc2
                        .subcollection(
                          'friends',
                          fromJson: TestUserModel.fromJson,
                          toJson: (user) => user.toJson(),
                        )
                        .doc('1')
                        .create(TestUserModel('Friend 1'));

                    await completer.onSync;

                    expect(
                      await get('users'),
                      {
                        "users": {
                          "users": {
                            "__values": {
                              "1": {"name": "User 1"},
                              "2": {"name": "User 2"},
                            },
                            "2": {
                              "friends": {
                                "__values": {
                                  "1": {"name": "Friend 1"},
                                }
                              }
                            }
                          },
                        },
                      },
                    );

                    expect(
                      await get('__resolver__'),
                      {
                        "__refs": {
                          Persistor.defaultKey.value: 1,
                          "users": 1,
                        },
                        "__values": {
                          ValueStore.root: Persistor.defaultKey.value,
                          "users": "users",
                        },
                      },
                    );

                    updatedUsersCollection
                        .doc('2')
                        .update(TestUserModel('User 2 updated'));

                    await completer.onSync;

                    expect(await exists('users'), false);

                    expect(
                      await get('updated_users'),
                      {
                        "users": {
                          "users": {
                            "__values": {
                              "1": {"name": "User 1"},
                              "2": {"name": "User 2 updated"},
                            },
                            "2": {
                              "friends": {
                                "__values": {
                                  "1": {"name": "Friend 1"},
                                }
                              }
                            }
                          }
                        }
                      },
                    );

                    expect(
                      await get('__resolver__'),
                      {
                        "__refs": {
                          Persistor.defaultKey.value: 1,
                          "updated_users": 1,
                        },
                        "__values": {
                          ValueStore.root: Persistor.defaultKey.value,
                          "users": "updated_users",
                        },
                      },
                    );
                  },
                );
              },
            );

            group(
              '6. key builder -> updated key builder',
              () {
                test(
                  'Moves the document and its subcollections from the previous store to the store specified by its updated key builder',
                  () async {
                    final userCollection = Loon.collection<TestUserModel>(
                      'users',
                      fromJson: TestUserModel.fromJson,
                      toJson: (user) => user.toJson(),
                      persistorSettings: PersistorSettings(
                        key: Persistor.keyBuilder<TestUserModel>(
                          (snap) {
                            if (snap.data.name.endsWith('updated')) {
                              return 'updated_users';
                            }
                            return 'users';
                          },
                        ),
                      ),
                    );

                    final userDoc = userCollection.doc('1');
                    final userDoc2 = userCollection.doc('2');

                    userDoc.create(TestUserModel('User 1'));
                    userDoc2.create(TestUserModel('User 2'));

                    userDoc2
                        .subcollection(
                          'friends',
                          fromJson: TestUserModel.fromJson,
                          toJson: (user) => user.toJson(),
                        )
                        .doc('1')
                        .create(TestUserModel('Friend 1'));

                    await completer.onSync;

                    expect(
                      await get('users'),
                      {
                        "users__1": {
                          "users": {
                            "__values": {
                              "1": {"name": "User 1"},
                            },
                          },
                        },
                        "users__2": {
                          "users": {
                            "__values": {
                              "2": {"name": "User 2"},
                            },
                            "2": {
                              "friends": {
                                "__values": {
                                  "1": {"name": "Friend 1"},
                                }
                              }
                            }
                          }
                        }
                      },
                    );

                    expect(
                      await get('__resolver__'),
                      {
                        "__refs": {
                          Persistor.defaultKey.value: 1,
                          "users": 2,
                        },
                        "__values": {
                          ValueStore.root: Persistor.defaultKey.value,
                        },
                        "users": {
                          "__refs": {
                            "users": 2,
                          },
                          "__values": {
                            "1": "users",
                            "2": "users",
                          },
                        },
                      },
                    );

                    userCollection
                        .doc('2')
                        .update(TestUserModel('User 2 updated'));

                    await completer.onSync;

                    expect(
                      await get('users'),
                      {
                        "users__1": {
                          "users": {
                            "__values": {
                              "1": {"name": "User 1"},
                            }
                          }
                        }
                      },
                    );

                    // Both `users__2` and its subcollections should have been moved to the `updated_users` data store.
                    expect(
                      await get('updated_users'),
                      {
                        "users__2": {
                          "users": {
                            "__values": {
                              "2": {"name": "User 2 updated"},
                            },
                            "2": {
                              "friends": {
                                "__values": {
                                  "1": {"name": "Friend 1"},
                                }
                              }
                            }
                          }
                        }
                      },
                    );

                    expect(
                      await get('__resolver__'),
                      {
                        "__refs": {
                          Persistor.defaultKey.value: 1,
                          "users": 1,
                          "updated_users": 1,
                        },
                        "__values": {
                          ValueStore.root: Persistor.defaultKey.value,
                        },
                        "users": {
                          "__refs": {
                            "users": 1,
                            "updated_users": 1,
                          },
                          "__values": {
                            "1": "users",
                            "2": "updated_users",
                          },
                        }
                      },
                    );
                  },
                );
              },
            );

            group(
              '7. value key -> key builder',
              () {
                test(
                  'Moves the document and its subcollections in the previous store to the updated store',
                  () async {
                    final usersCollection = Loon.collection<TestUserModel>(
                      'users',
                      fromJson: TestUserModel.fromJson,
                      toJson: (user) => user.toJson(),
                      persistorSettings: PersistorSettings(
                        key: Persistor.key('users'),
                      ),
                    );

                    final keyBuilderUsersCollection =
                        Loon.collection<TestUserModel>(
                      'users',
                      fromJson: TestUserModel.fromJson,
                      toJson: (user) => user.toJson(),
                      persistorSettings: PersistorSettings(
                        key: Persistor.keyBuilder(
                          (snap) => "users_${snap.id}",
                        ),
                      ),
                    );

                    usersCollection.doc('1').create(TestUserModel('User 1'));
                    usersCollection.doc('2').create(TestUserModel('User 2'));

                    await completer.onSync;

                    expect(await get('users'), {
                      "users": {
                        "users": {
                          "__values": {
                            "1": {"name": "User 1"},
                            "2": {"name": "User 2"},
                          },
                        }
                      }
                    });

                    expect(
                      await get('__resolver__'),
                      {
                        "__refs": {
                          Persistor.defaultKey.value: 1,
                          "users": 1,
                        },
                        "__values": {
                          ValueStore.root: Persistor.defaultKey.value,
                          "users": "users",
                        },
                      },
                    );

                    keyBuilderUsersCollection
                        .doc('1')
                        .update(TestUserModel('User 1 updated'));

                    await completer.onSync;

                    expect(await get('users'), {
                      "users": {
                        "users": {
                          "__values": {
                            "2": {"name": "User 2"},
                          },
                        }
                      }
                    });

                    expect(
                      await get('users_1'),
                      {
                        "users__1": {
                          "users": {
                            "__values": {
                              "1": {"name": "User 1 updated"},
                            },
                          }
                        }
                      },
                    );

                    expect(
                      await get('__resolver__'),
                      {
                        "__refs": {
                          Persistor.defaultKey.value: 1,
                          "users": 1,
                          "users_1": 1,
                        },
                        "__values": {
                          ValueStore.root: Persistor.defaultKey.value,
                          "users": "users",
                        },
                        "users": {
                          "__refs": {
                            "users_1": 1,
                          },
                          "__values": {
                            "1": "users_1",
                          }
                        }
                      },
                    );
                  },
                );
              },
            );

            group(
              '8. key builder -> value key',
              () {
                test(
                  'Moves the document and its subcollections in the previous store to the updated store',
                  () async {
                    final usersCollection = Loon.collection<TestUserModel>(
                      'users',
                      fromJson: TestUserModel.fromJson,
                      toJson: (user) => user.toJson(),
                      persistorSettings: PersistorSettings(
                        key: Persistor.keyBuilder(
                          (snap) => "users_${snap.id}",
                        ),
                      ),
                    );

                    final valueKeyCollection = Loon.collection<TestUserModel>(
                      'users',
                      fromJson: TestUserModel.fromJson,
                      toJson: (user) => user.toJson(),
                      persistorSettings: PersistorSettings(
                        key: Persistor.key('users'),
                      ),
                    );

                    usersCollection.doc('1').create(TestUserModel('User 1'));
                    usersCollection.doc('2').create(TestUserModel('User 2'));

                    await completer.onSync;

                    expect(await get('users_1'), {
                      "users__1": {
                        "users": {
                          "__values": {
                            "1": {"name": "User 1"},
                          },
                        }
                      }
                    });

                    expect(await get('users_2'), {
                      "users__2": {
                        "users": {
                          "__values": {
                            "2": {"name": "User 2"},
                          },
                        }
                      }
                    });

                    expect(
                      await get('__resolver__'),
                      {
                        "__refs": {
                          Persistor.defaultKey.value: 1,
                          "users_1": 1,
                          "users_2": 1,
                        },
                        "__values": {
                          ValueStore.root: Persistor.defaultKey.value,
                        },
                        "users": {
                          "__refs": {
                            "users_1": 1,
                            "users_2": 1,
                          },
                          "__values": {
                            "1": "users_1",
                            "2": "users_2",
                          }
                        }
                      },
                    );

                    valueKeyCollection
                        .doc('1')
                        .update(TestUserModel('User 1 updated'));

                    await completer.onSync;

                    expect(await get('users'), {
                      "users": {
                        "users": {
                          "__values": {
                            "1": {"name": "User 1 updated"},
                          },
                        }
                      }
                    });

                    expect(await exists('users_1'), false);
                    expect(await get('users_2'), {
                      "users__2": {
                        "users": {
                          "__values": {
                            "2": {"name": "User 2"},
                          },
                        }
                      }
                    });

                    expect(
                      await get('__resolver__'),
                      {
                        "__refs": {
                          Persistor.defaultKey.value: 1,
                          "users": 1,
                          "users_2": 1,
                        },
                        "__values": {
                          ValueStore.root: Persistor.defaultKey.value,
                          "users": "users",
                        },
                        "users": {
                          "__refs": {
                            "users_2": 1,
                          },
                          "__values": {
                            "2": "users_2",
                          }
                        }
                      },
                    );
                  },
                );
              },
            );
          },
        );

        group(
          'Global persistence',
          () {
            test(
              'Stores documents under the given value key',
              () async {
                configure(
                  settings: PersistorSettings(
                    key: Persistor.key('users'),
                  ),
                );

                final usersCollection = Loon.collection(
                  'users',
                  fromJson: TestUserModel.fromJson,
                  toJson: (user) => user.toJson(),
                );

                final userDoc = usersCollection.doc('1');

                userDoc.create(TestUserModel('User 1'));

                await completer.onSync;

                expect(
                  await get('users'),
                  {
                    "": {
                      "users": {
                        "__values": {
                          "1": {
                            "name": "User 1",
                          },
                        },
                      },
                    },
                  },
                );

                expect(
                  await get('__resolver__'),
                  {
                    "__refs": {
                      "users": 1,
                    },
                    "__values": {
                      "": "users",
                    },
                  },
                );
              },
            );

            test(
              'Stores documents using the given key builder',
              () async {
                configure(
                  settings: PersistorSettings(
                    key: Persistor.keyBuilder((snap) {
                      return switch (snap.data) {
                        TestUserModel _ => 'users',
                        _ => Persistor.defaultKey.value,
                      };
                    }),
                  ),
                );

                final usersCollection = Loon.collection(
                  'users',
                  fromJson: TestUserModel.fromJson,
                  toJson: (user) => user.toJson(),
                );

                final userDoc = usersCollection.doc('1');

                userDoc.create(TestUserModel('User 1'));
                Loon.collection('posts').doc('1').create({
                  "userId": 1,
                  "text": "This is a post",
                });

                await completer.onSync;

                expect(
                  await get('users'),
                  {
                    "users__1": {
                      "users": {
                        "__values": {
                          "1": {
                            "name": "User 1",
                          },
                        },
                      },
                    },
                  },
                );

                expect(
                  await get('__store__'),
                  {
                    "posts__1": {
                      "posts": {
                        "__values": {
                          "1": {
                            "userId": 1,
                            "text": "This is a post",
                          }
                        }
                      }
                    },
                  },
                );

                expect(
                  await get('__resolver__'),
                  {
                    "__refs": {
                      "users": 1,
                      Persistor.defaultKey.value: 2,
                    },
                    "__values": {
                      ValueStore.root: Persistor.defaultKey.value,
                    },
                    "users": {
                      "__refs": {
                        "users": 1,
                      },
                      "__values": {
                        "1": "users",
                      },
                    },
                    "posts": {
                      "__refs": {
                        Persistor.defaultKey.value: 1,
                      },
                      "__values": {
                        "1": Persistor.defaultKey.value,
                      },
                    },
                  },
                );
              },
            );
          },
        );

        test(
          'Data stored under the root collection is persisted in the root data store',
          () async {
            Loon.doc(
              'current_user',
              fromJson: TestUserModel.fromJson,
              toJson: (user) => user.toJson(),
            ).create(TestUserModel('Dan'));

            await completer.onSync;

            expect(
              await get('__store__'),
              {
                "": {
                  "root": {
                    "__values": {
                      "current_user": {'name': 'Dan'},
                    },
                  }
                }
              },
            );
          },
        );

        test(
          'Collections that disable persistence are not persisted',
          () async {
            final usersCollection = Loon.collection(
              'users',
              fromJson: TestUserModel.fromJson,
              toJson: (user) => user.toJson(),
            );

            final friendsCollection = Loon.collection(
              'friends',
              fromJson: TestUserModel.fromJson,
              toJson: (user) => user.toJson(),
              persistorSettings: const PersistorSettings(enabled: false),
            );

            usersCollection.doc('1').create(TestUserModel('User 1'));
            friendsCollection.doc('1').create(TestUserModel('Friend 1'));

            await completer.onSync;

            expect(
              await get('__store__'),
              {
                "": {
                  "users": {
                    "__values": {
                      "1": {'name': 'User 1'},
                    },
                  }
                }
              },
            );
          },
        );
      },
    );

    group('hydrate', () {
      test('Hydrates all data from persisted stores by default', () async {
        final userCollection = Loon.collection(
          'users',
          fromJson: TestUserModel.fromJson,
          toJson: (user) => user.toJson(),
        );
        final friendsCollection = Loon.collection(
          'friends',
          fromJson: TestUserModel.fromJson,
          toJson: (user) => user.toJson(),
        );

        final userFriendsCollection =
            Loon.collection('users').doc('1').subcollection<TestUserModel>(
                  'friends',
                  fromJson: TestUserModel.fromJson,
                  toJson: (user) => user.toJson(),
                  persistorSettings:
                      PersistorSettings(key: Persistor.key('my_friends')),
                );

        userCollection.doc('1').create(TestUserModel('User 1'));
        userCollection.doc('2').create(TestUserModel('User 2'));

        friendsCollection.doc('1').create(TestUserModel('Friend 1'));
        friendsCollection.doc('2').create(TestUserModel('Friend 2'));

        userFriendsCollection.doc('3').create(TestUserModel('Friend 3'));

        final currentUserDoc = Loon.doc('current_user_id');
        currentUserDoc.create('1');

        await completer.onSync;

        expect(await get('__store__'), {
          "": {
            "users": {
              "__values": {
                "1": {"name": "User 1"},
                "2": {"name": "User 2"},
              }
            },
            "friends": {
              "__values": {
                "1": {"name": "Friend 1"},
                "2": {"name": "Friend 2"},
              }
            },
            "root": {
              "__values": {
                "current_user_id": "1",
              },
            }
          },
        });

        expect(await get('my_friends'), {
          "users__1__friends": {
            "users": {
              "1": {
                "friends": {
                  "__values": {
                    "3": {"name": "Friend 3"},
                  }
                }
              }
            }
          }
        });

        expect(await get('__resolver__'), {
          "__refs": {
            Persistor.defaultKey.value: 1,
            "my_friends": 1,
          },
          "__values": {
            ValueStore.root: Persistor.defaultKey.value,
          },
          "users": {
            "__refs": {
              "my_friends": 1,
            },
            "1": {
              "__refs": {
                "my_friends": 1,
              },
              "__values": {
                "friends": "my_friends",
              },
            }
          }
        });

        Loon.configure(persistor: null);
        await Loon.clearAll();
        configure();

        expect(userCollection.exists(), false);
        expect(friendsCollection.exists(), false);
        expect(userFriendsCollection.exists(), false);

        await Loon.hydrate();

        expect(
          userCollection.get(),
          [
            DocumentSnapshot(
              doc: userCollection.doc('1'),
              data: TestUserModel('User 1'),
            ),
            DocumentSnapshot(
              doc: userCollection.doc('2'),
              data: TestUserModel('User 2'),
            ),
          ],
        );

        expect(friendsCollection.get(), [
          DocumentSnapshot(
            doc: friendsCollection.doc('1'),
            data: TestUserModel('Friend 1'),
          ),
          DocumentSnapshot(
            doc: friendsCollection.doc('2'),
            data: TestUserModel('Friend 2'),
          ),
        ]);

        expect(userFriendsCollection.get(), [
          DocumentSnapshot(
            doc: userFriendsCollection.doc('3'),
            data: TestUserModel('Friend 3'),
          ),
        ]);

        expect(
          currentUserDoc.get(),
          DocumentSnapshot(doc: currentUserDoc, data: '1'),
        );
      });

      test(
        "Only hydrates data under the provided paths when specified",
        () async {
          final userCollection = Loon.collection(
            'users',
            fromJson: TestUserModel.fromJson,
            toJson: (user) => user.toJson(),
          );
          final friendsCollection = Loon.collection(
            'friends',
            fromJson: TestUserModel.fromJson,
            toJson: (user) => user.toJson(),
          );

          final userFriendsCollection =
              Loon.collection('users').doc('1').subcollection<TestUserModel>(
                    'friends',
                    fromJson: TestUserModel.fromJson,
                    toJson: (user) => user.toJson(),
                    persistorSettings: PersistorSettings(
                      key: Persistor.key('user_friends'),
                    ),
                  );

          userCollection.doc('1').create(TestUserModel('User 1'));
          userCollection.doc('2').create(TestUserModel('User 2'));

          friendsCollection.doc('1').create(TestUserModel('Friend 1'));
          friendsCollection.doc('2').create(TestUserModel('Friend 2'));

          userFriendsCollection.doc('3').create(TestUserModel('Friend 3'));

          await completer.onSync;

          expect(await get('__store__'), {
            "": {
              "users": {
                "__values": {
                  "1": {"name": "User 1"},
                  "2": {"name": "User 2"},
                }
              },
              "friends": {
                "__values": {
                  "1": {"name": "Friend 1"},
                  "2": {"name": "Friend 2"},
                },
              },
            }
          });

          expect(await get('user_friends'), {
            "users__1__friends": {
              "users": {
                "1": {
                  "friends": {
                    "__values": {
                      "3": {"name": "Friend 3"},
                    }
                  }
                }
              }
            }
          });

          expect(await get('__resolver__'), {
            "__refs": {
              Persistor.defaultKey.value: 1,
              "user_friends": 1,
            },
            "__values": {
              ValueStore.root: Persistor.defaultKey.value,
            },
            "users": {
              "__refs": {
                "user_friends": 1,
              },
              "1": {
                "__refs": {
                  "user_friends": 1,
                },
                "__values": {
                  "friends": "user_friends",
                }
              }
            }
          });

          Loon.configure(persistor: null);
          await Loon.clearAll();
          configure();

          expect(userCollection.exists(), false);
          expect(friendsCollection.exists(), false);
          expect(userFriendsCollection.exists(), false);

          await Loon.hydrate([userCollection]);

          // Only the user collection and its subcollections should have been hydrated.
          // The `friends` collection should remain empty, while `users` and `users__1__friends`
          // should have been hydrated from persistence.
          //
          // Note that while the `__store__` data store contains the data for both the `users` collection
          // as well as the `friends` data, only the data in the store under the `users` path should
          // be extracted from the data store and delivered in the hydration response.

          expect(
            userCollection.get(),
            [
              DocumentSnapshot(
                doc: userCollection.doc('1'),
                data: TestUserModel('User 1'),
              ),
              DocumentSnapshot(
                doc: userCollection.doc('2'),
                data: TestUserModel('User 2'),
              ),
            ],
          );

          expect(friendsCollection.get(), []);

          expect(userFriendsCollection.get(), [
            DocumentSnapshot(
              doc: userFriendsCollection.doc('3'),
              data: TestUserModel('Friend 3'),
            ),
          ]);

          // If a subsequent request is made to hydrate a particular document from the `friends` data store,
          // then the already hydrated data can extract that additional data and deliver it in the hydration response.
          await Loon.hydrate([friendsCollection.doc('1')]);

          expect(friendsCollection.get(), [
            DocumentSnapshot(
              doc: friendsCollection.doc('1'),
              data: TestUserModel('Friend 1'),
            ),
          ]);
        },
      );

      test(
        "Hydrates root documents into the root collection",
        () async {
          final currentUserDoc = Loon.doc(
            'current_user',
            fromJson: TestUserModel.fromJson,
            toJson: (user) => user.toJson(),
          );

          currentUserDoc.create(TestUserModel('Dan'));

          await completer.onSync;

          expect(
            await get('__store__'),
            {
              "": {
                "root": {
                  "__values": {
                    "current_user": {'name': 'Dan'},
                  },
                }
              }
            },
          );

          Loon.configure(persistor: null);
          await Loon.clearAll();
          configure();

          await Loon.hydrate();

          expect(
            currentUserDoc.get(),
            DocumentSnapshot(
              doc: currentUserDoc,
              data: TestUserModel('Dan'),
            ),
          );
        },
      );

      test(
        "Hydrates only data under the specified root document",
        () async {
          final userCollection = Loon.collection(
            'users',
            fromJson: TestUserModel.fromJson,
            toJson: (user) => user.toJson(),
          );
          final currentUserDoc = Loon.doc(
            'current_user',
            fromJson: TestUserModel.fromJson,
            toJson: (user) => user.toJson(),
          );

          userCollection.doc('1').create(TestUserModel('User 1'));
          currentUserDoc.create(TestUserModel('Dan'));

          await completer.onSync;

          expect(
            await get('__store__'),
            {
              "": {
                "root": {
                  "__values": {
                    "current_user": {'name': 'Dan'},
                  },
                },
                "users": {
                  "__values": {
                    "1": {'name': 'User 1'},
                  }
                }
              }
            },
          );

          Loon.configure(persistor: null);
          await Loon.clearAll();
          configure();

          await Loon.hydrate([currentUserDoc]);

          expect(
            currentUserDoc.get(),
            DocumentSnapshot(
              doc: currentUserDoc,
              data: TestUserModel('Dan'),
            ),
          );

          expect(userCollection.exists(), false);
        },
      );

      test(
        "Hydrates only data under the root collection",
        () async {
          final userCollection = Loon.collection(
            'users',
            fromJson: TestUserModel.fromJson,
            toJson: (user) => user.toJson(),
          );
          final currentUserDoc = Loon.doc(
            'current_user',
            fromJson: TestUserModel.fromJson,
            toJson: (user) => user.toJson(),
          );

          userCollection.doc('1').create(TestUserModel('User 1'));
          currentUserDoc.create(TestUserModel('Dan'));

          await completer.onSync;

          expect(
            await get('__store__'),
            {
              "": {
                "root": {
                  "__values": {
                    "current_user": {'name': 'Dan'},
                  },
                },
                "users": {
                  "__values": {
                    "1": {'name': 'User 1'},
                  }
                }
              }
            },
          );

          Loon.configure(persistor: null);
          await Loon.clearAll();
          configure();

          await Loon.hydrate([Collection.root]);

          expect(
            currentUserDoc.get(),
            DocumentSnapshot(
              doc: currentUserDoc,
              data: TestUserModel('Dan'),
            ),
          );

          expect(userCollection.exists(), false);
        },
      );
    });

    group(
      'clear',
      () {
        test(
          "Deletes the collection's data store",
          () async {
            final userCollection = Loon.collection(
              'users',
              fromJson: TestUserModel.fromJson,
              toJson: (user) => user.toJson(),
            );

            userCollection.doc('1').create(TestUserModel('User 1'));
            userCollection.doc('2').create(TestUserModel('User 2'));

            await completer.onSync;

            expect(await exists('__store__'), true);

            userCollection.delete();

            await completer.onSync;

            expect(await exists('__store__'), false);
          },
        );

        // In this scenario, the user collection is spread across multiple data stores. Since each of those
        // data stores are empty after the collection is cleared, they should all be deleted.
        test(
          "Deletes all of the collection's data stores",
          () async {
            final userCollection = Loon.collection<TestUserModel>(
              'users',
              fromJson: TestUserModel.fromJson,
              toJson: (user) => user.toJson(),
              persistorSettings: PersistorSettings(
                key: Persistor.keyBuilder((snap) => 'users_${snap.id}'),
              ),
            );

            userCollection.doc('1').create(TestUserModel('User 1'));
            userCollection.doc('2').create(TestUserModel('User 2'));
            userCollection.doc('3').create(TestUserModel('User 3'));

            await completer.onSync;

            expect(await exists('users_1'), true);
            expect(await exists('users_2'), true);
            expect(await exists('users_3'), true);

            userCollection.delete();

            await completer.onSync;

            expect(await exists('users_1'), false);
            expect(await exists('users_2'), false);
            expect(await exists('users_3'), false);
          },
        );

        test(
          "Deletes the collection's subcollection data store",
          () async {
            final userCollection = Loon.collection(
              'users',
              fromJson: TestUserModel.fromJson,
              toJson: (user) => user.toJson(),
            );
            final friendsCollection = userCollection.doc('1').subcollection(
                  'friends',
                  fromJson: TestUserModel.fromJson,
                  toJson: (user) => user.toJson(),
                  persistorSettings: PersistorSettings(
                    key: Persistor.key('friends'),
                  ),
                );

            userCollection.doc('1').create(TestUserModel('User 1'));
            userCollection.doc('2').create(TestUserModel('User 2'));
            friendsCollection.doc('1').create(TestUserModel('Friend 1'));

            await completer.onSync;

            expect(await exists('__store__'), true);
            expect(await exists('friends'), true);

            userCollection.delete();

            await completer.onSync;

            expect(await exists('__store__'), false);
            expect(await exists('friends'), false);
          },
        );

        // In this scenario, multiple collections share a data store and therefore
        // the store should not be deleted since it still has documents from another collection.
        test(
          'Retains data stores that still contain other collections',
          () async {
            final userCollection = Loon.collection(
              'users',
              fromJson: TestUserModel.fromJson,
              toJson: (user) => user.toJson(),
            );
            final friendsCollection = Loon.collection<TestUserModel>(
              'friends',
              fromJson: TestUserModel.fromJson,
              toJson: (user) => user.toJson(),
            );

            userCollection.doc('1').create(TestUserModel('User 1'));
            userCollection.doc('2').create(TestUserModel('User 2'));
            friendsCollection.doc('1').create(TestUserModel('Friend 1'));
            friendsCollection.doc('2').create(TestUserModel('Friend 2'));

            await completer.onSync;

            expect(
              await get('__store__'),
              {
                "": {
                  "users": {
                    "__values": {
                      "1": {'name': 'User 1'},
                      "2": {'name': 'User 2'},
                    }
                  },
                  "friends": {
                    "__values": {
                      "1": {'name': 'Friend 1'},
                      "2": {'name': 'Friend 2'},
                    },
                  },
                }
              },
            );

            userCollection.delete();

            await completer.onSync;

            expect(
              await get('__store__'),
              {
                "": {
                  "friends": {
                    "__values": {
                      "1": {'name': 'Friend 1'},
                      "2": {'name': 'Friend 2'},
                    },
                  },
                }
              },
            );
          },
        );
      },
    );

    group(
      'clearAll',
      () {
        test(
          "Deletes all data stores",
          () async {
            final userCollection = Loon.collection(
              'users',
              fromJson: TestUserModel.fromJson,
              toJson: (user) => user.toJson(),
              persistorSettings: PersistorSettings(
                key: Persistor.key('users'),
              ),
            );

            final userDoc = userCollection.doc('1');
            final userDoc2 = userCollection.doc('2');
            final user = TestUserModel('User 1');
            final user2 = TestUserModel('User 2');

            userDoc.create(user);
            userDoc2.create(user2);

            await completer.onSync;

            expect(await exists('users'), true);
            expect(await exists('__resolver__'), true);

            await Loon.clearAll();

            expect(await exists('users'), false);
            expect(await exists('__resolver__'), false);

            userDoc.create(user);
            userDoc2.create(user2);

            await completer.onSync;

            expect(await exists('users'), true);
          },
        );
      },
    );

    test('Sequences operations correctly', () async {
      final List<String> operations = [];
      Loon.configure(
        persistor: TestPersistor(
          onClear: (_) {
            operations.add('clear');
          },
          onClearAll: () {
            operations.add('clearAll');
          },
          onHydrate: (_) {
            operations.add('hydrate');
          },
          onPersist: (_) {
            operations.add('persist');
          },
        ),
      );

      final userCollection = Loon.collection(
        'users',
        fromJson: TestUserModel.fromJson,
        toJson: (user) => user.toJson(),
      );

      userCollection.doc('1').create(TestUserModel('User 1'));
      userCollection.doc('2').create(TestUserModel('User 2'));
      Loon.hydrate();
      userCollection.delete();
      userCollection.doc('3').create(TestUserModel('User 3'));

      await Loon.hydrate();

      expect(operations, [
        'persist',
        'hydrate',
        'clear',
        'persist',
        'hydrate',
      ]);

      expect(
        userCollection.get(),
        [
          DocumentSnapshot(
            doc: userCollection.doc('3'),
            data: TestUserModel('User 3'),
          ),
        ],
      );
    });
  });

  group(
    'Encrypted Persistor Test Runner',
    () {
      const encryptedSettings = PersistorSettings(encrypted: true);

      setUp(() {
        configure(settings: encryptedSettings);
      });

      tearDown(() async {
        await Loon.clearAll();
      });

      group('hydrate', () {
        test(
          'Merges data from plaintext and encrypted persistence stores into collections',
          () async {
            final userCollection = Loon.collection<TestUserModel>(
              'users',
              fromJson: TestUserModel.fromJson,
              toJson: (user) => user.toJson(),
              persistorSettings: const PersistorSettings(encrypted: false),
            );
            final encryptedUsersCollection = Loon.collection<TestUserModel>(
              'users',
              fromJson: TestUserModel.fromJson,
              toJson: (user) => user.toJson(),
              persistorSettings: const PersistorSettings(encrypted: true),
            );

            userCollection.doc('1').create(TestUserModel('User 1'));
            encryptedUsersCollection.doc('2').create(TestUserModel('User 2'));

            await completer.onSync;

            expect(await get('__store__'), {
              "": {
                "users": {
                  "__values": {
                    '1': {'name': 'User 1'},
                  },
                },
              }
            });

            expect(await get('__store__', encrypted: true), {
              "": {
                "users": {
                  "__values": {
                    '2': {'name': 'User 2'},
                  },
                },
              }
            });

            Loon.configure(persistor: null);
            await Loon.clearAll();
            configure(settings: encryptedSettings);

            expect(userCollection.exists(), false);

            await Loon.hydrate();

            expect(
              userCollection.get(),
              [
                DocumentSnapshot(
                  doc: userCollection.doc('1'),
                  data: TestUserModel('User 1'),
                ),
                DocumentSnapshot(
                  doc: userCollection.doc('2'),
                  data: TestUserModel('User 2'),
                ),
              ],
            );
          },
        );

        // This scenario takes a bit of a description. In the situation where a data store for a collection is unencrypted,
        // but encryption settings now specify that the collection should be encrypted, then the unencrypted store should
        // be hydrated into memory, but any subsequent persistence calls for that collection should move the updated data
        // from the unencrypted data store to the encrypted data store. Once all the data has been moved, the unencrypted
        // store should be deleted.
        test('Encrypts collections hydrated from unencrypted stores', () async {
          configure(settings: const PersistorSettings());

          final usersCollection = Loon.collection(
            'users',
            fromJson: TestUserModel.fromJson,
            toJson: (user) => user.toJson(),
          );

          usersCollection.doc('1').create(TestUserModel('User 1'));
          usersCollection.doc('2').create(TestUserModel('User 2'));

          await completer.onSync;

          expect(
            await get('__store__'),
            {
              "": {
                "users": {
                  "__values": {
                    "1": {"name": "User 1"},
                    "2": {"name": "User 2"},
                  }
                }
              }
            },
          );

          Loon.configure(persistor: null);
          await Loon.clearAll();
          configure(settings: encryptedSettings);

          await Loon.hydrate();

          expect(
            usersCollection.get(),
            [
              DocumentSnapshot(
                doc: usersCollection.doc('1'),
                data: TestUserModel('User 1'),
              ),
              DocumentSnapshot(
                doc: usersCollection.doc('2'),
                data: TestUserModel('User 2'),
              ),
            ],
          );

          usersCollection.doc('3').create(TestUserModel('User 3'));

          await completer.onSync;

          // The new user should have been written to the encrypted data store, since the persistor was configured with encryption
          // enabled globally.
          expect(
            await get('__store__', encrypted: true),
            {
              "": {
                "users": {
                  "__values": {
                    "3": {'name': 'User 3'},
                  }
                },
              }
            },
          );

          // The existing hydrated data should still be unencrypted, as the documents are not moved until they are updated.
          expect(
            await get('__store__'),
            {
              "": {
                "users": {
                  "__values": {
                    "1": {"name": "User 1"},
                    "2": {"name": "User 2"},
                  }
                }
              }
            },
          );

          usersCollection.doc('1').update(TestUserModel('User 1 updated'));
          usersCollection.doc('2').update(TestUserModel('User 2 updated'));

          await completer.onSync;

          // The documents should now have been updated to exist in the encrypted store.
          expect(
            await get('__store__', encrypted: true),
            {
              "": {
                "users": {
                  "__values": {
                    "1": {'name': 'User 1 updated'},
                    "2": {'name': 'User 2 updated'},
                    "3": {"name": "User 3"},
                  },
                },
              }
            },
          );

          // The now empty plaintext root data store should have been deleted.
          expect(await exists('__store__'), false);
        });
      });

      group(
        'persist',
        () {
          test('Encrypts data when enabled globally for all collections',
              () async {
            final userCollection = Loon.collection(
              'users',
              fromJson: TestUserModel.fromJson,
              toJson: (user) => user.toJson(),
            );

            final user1 = TestUserModel('User 1');
            final userDoc1 = userCollection.doc('1');
            final user2 = TestUserModel('User 2');
            final userDoc2 = userCollection.doc('2');

            userDoc1.create(user1);
            userDoc2.create(user2);

            await completer.onSync;

            expect(
              await get('__store__', encrypted: true),
              {
                "": {
                  "users": {
                    "__values": {
                      "1": {'name': 'User 1'},
                      "2": {'name': 'User 2'},
                    }
                  }
                }
              },
            );
          });

          test('Encrypts data when explicitly enabled for a collection',
              () async {
            configure(settings: const PersistorSettings());

            final friendsCollection = Loon.collection<TestUserModel>(
              'friends',
              fromJson: TestUserModel.fromJson,
              toJson: (user) => user.toJson(),
            );

            final usersCollection = Loon.collection<TestUserModel>(
              'users',
              fromJson: TestUserModel.fromJson,
              toJson: (user) => user.toJson(),
              persistorSettings: const PersistorSettings(encrypted: true),
            );

            friendsCollection.doc('1').create(TestUserModel('Friend 1'));
            usersCollection.doc('1').create(TestUserModel('User 1'));
            usersCollection.doc('2').create(TestUserModel('User 2'));

            await completer.onSync;

            expect(
              await get('__store__'),
              {
                "": {
                  "friends": {
                    "__values": {
                      "1": {'name': 'Friend 1'},
                    }
                  },
                }
              },
            );

            expect(
              await get('__store__', encrypted: true),
              {
                "": {
                  "users": {
                    "__values": {
                      "1": {'name': 'User 1'},
                      "2": {'name': 'User 2'},
                    }
                  },
                }
              },
            );
          });
          test('Subcollections inherit parent encryption settings', () async {
            configure(settings: const PersistorSettings());

            final usersCollection = Loon.collection<TestUserModel>(
              'users',
              fromJson: TestUserModel.fromJson,
              toJson: (user) => user.toJson(),
              persistorSettings: const PersistorSettings(encrypted: true),
            );

            final user1FriendsCollection =
                usersCollection.doc('1').subcollection(
                      'friends',
                      fromJson: TestUserModel.fromJson,
                      toJson: (friend) => friend.toJson(),
                    );

            usersCollection.doc('1').create(TestUserModel('User 1'));
            usersCollection.doc('2').create(TestUserModel('User 2'));
            user1FriendsCollection.doc('1').create(TestUserModel('Friend 1'));

            await completer.onSync;

            expect(await exists('__store__'), false);

            expect(
              await get('__store__', encrypted: true),
              {
                "": {
                  "users": {
                    "__values": {
                      "1": {'name': 'User 1'},
                      "2": {'name': 'User 2'},
                    },
                    "1": {
                      "friends": {
                        "__values": {
                          "1": {
                            "name": "Friend 1",
                          }
                        }
                      }
                    }
                  },
                }
              },
            );
          });

          test('Subcollections can override parent encryption settings',
              () async {
            configure(settings: const PersistorSettings());

            final usersCollection = Loon.collection<TestUserModel>(
              'users',
              fromJson: TestUserModel.fromJson,
              toJson: (user) => user.toJson(),
              persistorSettings: const PersistorSettings(encrypted: true),
            );

            final user1FriendsCollection = usersCollection
                .doc('1')
                .subcollection(
                  'friends',
                  fromJson: TestUserModel.fromJson,
                  toJson: (friend) => friend.toJson(),
                  persistorSettings: const PersistorSettings(encrypted: false),
                );

            usersCollection.doc('1').create(TestUserModel('User 1'));
            usersCollection.doc('2').create(TestUserModel('User 2'));
            user1FriendsCollection.doc('1').create(TestUserModel('Friend 1'));

            await completer.onSync;

            expect(
              await get('__store__'),
              {
                "": {
                  "users": {
                    "1": {
                      "friends": {
                        "__values": {
                          "1": {
                            "name": "Friend 1",
                          }
                        }
                      }
                    }
                  },
                }
              },
            );

            expect(
              await get('__store__', encrypted: true),
              {
                "": {
                  "users": {
                    "__values": {
                      "1": {'name': 'User 1'},
                      "2": {'name': 'User 2'},
                    },
                  },
                }
              },
            );
          });

          test(
            'Does not encrypt data when explicitly disabled for a collection',
            () async {
              final usersCollection = Loon.collection<TestUserModel>(
                'users',
                fromJson: TestUserModel.fromJson,
                toJson: (user) => user.toJson(),
                persistorSettings: const PersistorSettings(encrypted: false),
              );

              usersCollection.doc('1').create(TestUserModel('User 1'));
              usersCollection.doc('2').create(TestUserModel('User 2'));

              await completer.onSync;

              expect(
                await get('__store__'),
                {
                  "": {
                    "users": {
                      "__values": {
                        "1": {'name': 'User 1'},
                        "2": {'name': 'User 2'},
                      }
                    },
                  }
                },
              );

              expect(await exists('__store__', encrypted: true), false);
            },
          );
        },
      );
    },
  );
}
