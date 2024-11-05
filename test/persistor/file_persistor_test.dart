import 'dart:convert';
import 'dart:io';
import 'package:flutter_test/flutter_test.dart';
import 'package:loon/loon.dart';

// ignore: depend_on_referenced_packages
import 'package:path_provider_platform_interface/path_provider_platform_interface.dart';
// ignore: depend_on_referenced_packages
import 'package:plugin_platform_interface/plugin_platform_interface.dart';

import '../models/test_file_persistor.dart';
import '../models/test_large_model.dart';
import '../models/test_user_model.dart';
import '../utils.dart';

late Directory testDirectory;

final logger = Logger('FilePersistorTest');

class MockPathProvider extends Fake
    with MockPlatformInterfaceMixin
    implements PathProviderPlatform {
  getApplicationDocumentsDirectory() {
    return testDirectory;
  }

  @override
  getApplicationDocumentsPath() async {
    return testDirectory.path;
  }
}

void main() {
  late FilePersistorCompleter completer;

  setUp(() {
    completer = TestFilePersistor.completer = FilePersistorCompleter();
    testDirectory = Directory.systemTemp.createTempSync('test_dir');
    Directory("${testDirectory.path}/loon").createSync();
    final mockPathProvider = MockPathProvider();
    PathProviderPlatform.instance = mockPathProvider;

    Loon.configure(persistor: TestFilePersistor());
  });

  tearDown(() async {
    testDirectory.deleteSync(recursive: true);
    await Loon.clearAll();
  });

  group('Plaintext FilePersistor', () {
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

            final file = File('${testDirectory.path}/loon/__store__.json');
            final json = jsonDecode(file.readAsStringSync());

            expect(
              json,
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
            final resolverFile =
                File('${testDirectory.path}/loon/__resolver__.json');
            expect(resolverFile.existsSync(), false);
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

            final file = File('${testDirectory.path}/loon/__store__.json');
            final json = jsonDecode(file.readAsStringSync());

            expect(
              json,
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

            final file = File('${testDirectory.path}/loon/__store__.json');
            final json = jsonDecode(file.readAsStringSync());

            expect(
              json,
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

            var file = File('${testDirectory.path}/loon/__store__.json');
            var json = jsonDecode(file.readAsStringSync());

            expect(
              json,
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

            file = File('${testDirectory.path}/loon/__store__.json');
            json = jsonDecode(file.readAsStringSync());

            expect(
              json,
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
          'Deletes empty files',
          () async {
            final userCollection = Loon.collection(
              'users',
              fromJson: TestUserModel.fromJson,
              toJson: (user) => user.toJson(),
            );

            userCollection.doc('1').create(TestUserModel('User 1'));
            userCollection.doc('2').create(TestUserModel('User 2'));

            final file = File('${testDirectory.path}/loon/__store__.json');

            await completer.onSync;

            expect(file.existsSync(), true);

            // If all documents of a file are deleted, the file itself should be deleted.
            userCollection.doc('1').delete();
            userCollection.doc('2').delete();

            await completer.onSync;

            expect(file.existsSync(), false);
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

            final storeFile = File('${testDirectory.path}/loon/__store__.json');
            final friendsFile = File('${testDirectory.path}/loon/friends.json');
            var storeJson = jsonDecode(storeFile.readAsStringSync());
            var friendsJson = jsonDecode(friendsFile.readAsStringSync());

            expect(
              storeJson,
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
              friendsJson,
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

            final resolverFile =
                File('${testDirectory.path}/loon/__resolver__.json');
            var resolverJson = jsonDecode(resolverFile.readAsStringSync());

            expect(
              resolverJson,
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

            friendsJson = jsonDecode(friendsFile.readAsStringSync());
            expect(
              friendsJson,
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

            resolverJson = jsonDecode(resolverFile.readAsStringSync());
            expect(
              resolverJson,
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

            expect(friendsFile.existsSync(), false);

            resolverJson = jsonDecode(resolverFile.readAsStringSync());
            expect(
              resolverJson,
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

            final usersFile = File('${testDirectory.path}/loon/users.json');
            final otherUsersFile =
                File('${testDirectory.path}/loon/other_users.json');
            var usersJson = jsonDecode(usersFile.readAsStringSync());
            var otherUsersJson = jsonDecode(otherUsersFile.readAsStringSync());

            expect(
              usersJson,
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
              otherUsersJson,
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

            final resolverFile =
                File('${testDirectory.path}/loon/__resolver__.json');
            var resolverJson = jsonDecode(resolverFile.readAsStringSync());

            expect(
              resolverJson,
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

            expect(usersFile.existsSync(), false);
            expect(
              otherUsersJson,
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

            resolverJson = jsonDecode(resolverFile.readAsStringSync());
            expect(
              resolverJson,
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

            expect(otherUsersFile.existsSync(), false);

            resolverJson = jsonDecode(resolverFile.readAsStringSync());
            expect(
              resolverJson,
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

            final storeFile = File('${testDirectory.path}/loon/__store__.json');
            final usersFile = File('${testDirectory.path}/loon/users.json');
            final usersJson = jsonDecode(usersFile.readAsStringSync());

            // All data is stored in the users.json
            expect(storeFile.existsSync(), false);

            expect(
              usersJson,
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

            final resolverFile =
                File('${testDirectory.path}/loon/__resolver__.json');
            final resolverJson = jsonDecode(resolverFile.readAsStringSync());

            expect(
              resolverJson,
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

            final usersFile = File('${testDirectory.path}/loon/users.json');
            final friendsFile = File('${testDirectory.path}/loon/friends.json');
            final usersJson = jsonDecode(usersFile.readAsStringSync());
            final friendsJson = jsonDecode(friendsFile.readAsStringSync());

            expect(
              usersJson,
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
              friendsJson,
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

            final resolverFile =
                File('${testDirectory.path}/loon/__resolver__.json');
            final resolverJson = jsonDecode(resolverFile.readAsStringSync());

            // Since the friends collection under users__2 specifies a "friends" key,
            // this overrides the parent path's "users" key on the users collection and
            // therefore resolves the friends documents to the "friends" data store.
            expect(
              resolverJson,
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

            final users1File = File('${testDirectory.path}/loon/users_1.json');
            final users2File = File('${testDirectory.path}/loon/users_2.json');
            final users1Json = jsonDecode(users1File.readAsStringSync());
            final users2Json = jsonDecode(users2File.readAsStringSync());

            expect(
              users1Json,
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
              users2Json,
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

            final resolverFile =
                File('${testDirectory.path}/loon/__resolver__.json');
            final resolverJson = jsonDecode(resolverFile.readAsStringSync());

            expect(
              resolverJson,
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

            final users1File = File('${testDirectory.path}/loon/users_1.json');
            final users2File = File('${testDirectory.path}/loon/users_2.json');
            final users1Json = jsonDecode(users1File.readAsStringSync());
            final users2Json = jsonDecode(users2File.readAsStringSync());
            final friends1File =
                File('${testDirectory.path}/loon/friends_1.json');
            final friends2File =
                File('${testDirectory.path}/loon/friends_2.json');
            final friends1Json = jsonDecode(friends1File.readAsStringSync());
            final friends2Json = jsonDecode(friends2File.readAsStringSync());

            expect(
              users1Json,
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
              friends1Json,
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
              users2Json,
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
              friends2Json,
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

            final resolverFile =
                File('${testDirectory.path}/loon/__resolver__.json');
            final resolverJson = jsonDecode(resolverFile.readAsStringSync());

            expect(
              resolverJson,
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

            final usersFile = File('${testDirectory.path}/loon/users.json');
            final storeFile = File('${testDirectory.path}/loon/__store__.json');
            final usersJson = jsonDecode(usersFile.readAsStringSync());
            final storeJson = jsonDecode(storeFile.readAsStringSync());

            expect(
              usersJson,
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
              storeJson,
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

            final resolverFile =
                File('${testDirectory.path}/loon/__resolver__.json');
            final resolverJson = jsonDecode(resolverFile.readAsStringSync());

            // Since the friends collection under users__2 specifies a "friends" key,
            // this overrides the parent path's "users" key on the users collection and
            // therefore resolves the friends documents to the "friends" data store.
            expect(
              resolverJson,
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

                    final storeFile =
                        File('${testDirectory.path}/loon/__store__.json');
                    var storeJson = jsonDecode(storeFile.readAsStringSync());

                    expect(
                      storeJson,
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

                    final resolverFile =
                        File('${testDirectory.path}/loon/__resolver__.json');
                    expect(resolverFile.existsSync(), false);

                    updatedUsersCollection
                        .doc('1')
                        .update(TestUserModel('User 1 updated'));

                    await completer.onSync;

                    final otherUsersFile =
                        File('${testDirectory.path}/loon/other_users.json');
                    var otherUsersJson =
                        jsonDecode(otherUsersFile.readAsStringSync());

                    expect(storeFile.existsSync(), false);

                    expect(
                      otherUsersJson,
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

                    final resolverJson =
                        jsonDecode(resolverFile.readAsStringSync());
                    expect(
                      resolverJson,
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

                    final storeFile =
                        File('${testDirectory.path}/loon/__store__.json');
                    var storeJson = jsonDecode(storeFile.readAsStringSync());

                    expect(
                      storeJson,
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

                    final resolverFile =
                        File('${testDirectory.path}/loon/__resolver__.json');
                    expect(resolverFile.existsSync(), false);

                    updatedUsersCollection
                        .doc('1')
                        .update(TestUserModel('User 1 updated'));

                    await completer.onSync;

                    storeJson = jsonDecode(storeFile.readAsStringSync());
                    expect(
                      storeJson,
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

                    final users1File =
                        File('${testDirectory.path}/loon/users_1.json');
                    var users1Json = jsonDecode(users1File.readAsStringSync());

                    expect(
                      users1Json,
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

                    var resolverJson =
                        jsonDecode(resolverFile.readAsStringSync());
                    expect(
                      resolverJson,
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

                    final storeFile =
                        File('${testDirectory.path}/loon/__store__.json');
                    expect(storeFile.existsSync(), false);

                    final usersFile =
                        File('${testDirectory.path}/loon/users.json');
                    var usersJson = jsonDecode(usersFile.readAsStringSync());

                    expect(
                      usersJson,
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

                    final resolverFile =
                        File('${testDirectory.path}/loon/__resolver__.json');
                    var resolverJson =
                        jsonDecode(resolverFile.readAsStringSync());

                    expect(
                      resolverJson,
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

                    var storeJson = jsonDecode(storeFile.readAsStringSync());

                    expect(
                      storeJson,
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

                    expect(usersFile.existsSync(), false);

                    resolverJson = jsonDecode(resolverFile.readAsStringSync());
                    expect(
                      resolverJson,
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

                    final storeFile =
                        File('${testDirectory.path}/loon/__store__.json');
                    expect(storeFile.existsSync(), false);

                    final users1File =
                        File('${testDirectory.path}/loon/users_1.json');
                    var users1Json = jsonDecode(users1File.readAsStringSync());

                    expect(
                      users1Json,
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

                    final users2File =
                        File('${testDirectory.path}/loon/users_2.json');
                    var users2Json = jsonDecode(users2File.readAsStringSync());

                    expect(
                      users2Json,
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

                    final resolverFile =
                        File('${testDirectory.path}/loon/__resolver__.json');
                    var resolverJson =
                        jsonDecode(resolverFile.readAsStringSync());

                    expect(
                      resolverJson,
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

                    var storeJson = jsonDecode(storeFile.readAsStringSync());

                    expect(
                      storeJson,
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

                    expect(users1File.existsSync(), false);

                    users2Json = jsonDecode(users2File.readAsStringSync());
                    expect(
                      users2Json,
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

                    resolverJson = jsonDecode(resolverFile.readAsStringSync());
                    expect(
                      resolverJson,
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

                    final usersFile =
                        File('${testDirectory.path}/loon/users.json');
                    var usersJson = jsonDecode(usersFile.readAsStringSync());

                    expect(
                      usersJson,
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

                    var resolverFile =
                        File('${testDirectory.path}/loon/__resolver__.json');
                    var resolverJson =
                        jsonDecode(resolverFile.readAsStringSync());

                    expect(
                      resolverJson,
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

                    expect(usersFile.existsSync(), false);

                    final updatedUsersFile =
                        File('${testDirectory.path}/loon/updated_users.json');
                    final updatedUsersJson =
                        jsonDecode(updatedUsersFile.readAsStringSync());

                    expect(
                      updatedUsersJson,
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

                    resolverFile =
                        File('${testDirectory.path}/loon/__resolver__.json');
                    resolverJson = jsonDecode(resolverFile.readAsStringSync());

                    expect(
                      resolverJson,
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

                    final usersFile =
                        File('${testDirectory.path}/loon/users.json');
                    var usersJson = jsonDecode(usersFile.readAsStringSync());

                    expect(
                      usersJson,
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

                    var resolverFile =
                        File('${testDirectory.path}/loon/__resolver__.json');
                    var resolverJson =
                        jsonDecode(resolverFile.readAsStringSync());

                    expect(
                      resolverJson,
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

                    usersJson = jsonDecode(usersFile.readAsStringSync());
                    expect(
                      usersJson,
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

                    final updatedUsersFile =
                        File('${testDirectory.path}/loon/updated_users.json');
                    final updatedUsersJson =
                        jsonDecode(updatedUsersFile.readAsStringSync());

                    // Both `users__2` and its subcollections should have been moved to the `updated_users` data store.
                    expect(
                      updatedUsersJson,
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

                    resolverFile =
                        File('${testDirectory.path}/loon/__resolver__.json');
                    resolverJson = jsonDecode(resolverFile.readAsStringSync());

                    expect(
                      resolverJson,
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

                    final usersFile =
                        File('${testDirectory.path}/loon/users.json');
                    var usersJson = jsonDecode(usersFile.readAsStringSync());

                    expect(usersJson, {
                      "users": {
                        "users": {
                          "__values": {
                            "1": {"name": "User 1"},
                            "2": {"name": "User 2"},
                          },
                        }
                      }
                    });

                    final resolverFile =
                        File('${testDirectory.path}/loon/__resolver__.json');
                    var resolverJson =
                        jsonDecode(resolverFile.readAsStringSync());

                    expect(
                      resolverJson,
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

                    usersJson = jsonDecode(usersFile.readAsStringSync());
                    expect(usersJson, {
                      "users": {
                        "users": {
                          "__values": {
                            "2": {"name": "User 2"},
                          },
                        }
                      }
                    });

                    final users1File =
                        File('${testDirectory.path}/loon/users_1.json');
                    var users1Json = jsonDecode(users1File.readAsStringSync());

                    expect(
                      users1Json,
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

                    resolverJson = jsonDecode(resolverFile.readAsStringSync());
                    expect(
                      resolverJson,
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

                    final users1File =
                        File('${testDirectory.path}/loon/users_1.json');
                    var users1Json = jsonDecode(users1File.readAsStringSync());

                    expect(users1Json, {
                      "users__1": {
                        "users": {
                          "__values": {
                            "1": {"name": "User 1"},
                          },
                        }
                      }
                    });

                    final users2File =
                        File('${testDirectory.path}/loon/users_2.json');
                    var users2Json = jsonDecode(users2File.readAsStringSync());

                    expect(users2Json, {
                      "users__2": {
                        "users": {
                          "__values": {
                            "2": {"name": "User 2"},
                          },
                        }
                      }
                    });

                    final resolverFile =
                        File('${testDirectory.path}/loon/__resolver__.json');
                    var resolverJson =
                        jsonDecode(resolverFile.readAsStringSync());

                    expect(
                      resolverJson,
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

                    final usersFile =
                        File('${testDirectory.path}/loon/users.json');
                    final usersJson = jsonDecode(usersFile.readAsStringSync());
                    expect(usersJson, {
                      "users": {
                        "users": {
                          "__values": {
                            "1": {"name": "User 1 updated"},
                          },
                        }
                      }
                    });

                    expect(users1File.existsSync(), false);

                    users2Json = jsonDecode(users2File.readAsStringSync());
                    expect(users2Json, {
                      "users__2": {
                        "users": {
                          "__values": {
                            "2": {"name": "User 2"},
                          },
                        }
                      }
                    });

                    resolverJson = jsonDecode(resolverFile.readAsStringSync());
                    expect(
                      resolverJson,
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
                Loon.configure(
                  persistor: TestFilePersistor(
                    settings: PersistorSettings(
                      key: Persistor.key('users'),
                    ),
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

                final usersFile = File('${testDirectory.path}/loon/users.json');
                final usersJson = jsonDecode(usersFile.readAsStringSync());

                expect(
                  usersJson,
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

                final resolverFile =
                    File('${testDirectory.path}/loon/__resolver__.json');
                final resolverJson =
                    jsonDecode(resolverFile.readAsStringSync());

                expect(
                  resolverJson,
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
                Loon.configure(
                  persistor: TestFilePersistor(
                    settings: PersistorSettings(
                      key: Persistor.keyBuilder((snap) {
                        return switch (snap.data) {
                          TestUserModel _ => 'users',
                          _ => Persistor.defaultKey.value,
                        };
                      }),
                    ),
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

                final usersFile = File('${testDirectory.path}/loon/users.json');
                final usersJson = jsonDecode(usersFile.readAsStringSync());

                expect(
                  usersJson,
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

                final storeFile =
                    File('${testDirectory.path}/loon/__store__.json');
                final storeJson = jsonDecode(storeFile.readAsStringSync());

                expect(
                  storeJson,
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

                final resolverFile =
                    File('${testDirectory.path}/loon/__resolver__.json');
                final resolverJson =
                    jsonDecode(resolverFile.readAsStringSync());

                expect(
                  resolverJson,
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

            final file = File('${testDirectory.path}/loon/__store__.json');
            final json = jsonDecode(file.readAsStringSync());

            expect(
              json,
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

            final file = File('${testDirectory.path}/loon/__store__.json');
            final json = jsonDecode(file.readAsStringSync());

            expect(
              json,
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
      test('Hydrates all data from persistence files by default', () async {
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

        final storeFile = File('${testDirectory.path}/loon/__store__.json');
        final storeJson = jsonDecode(storeFile.readAsStringSync());

        expect(storeJson, {
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

        final myFriendsFile =
            File('${testDirectory.path}/loon/my_friends.json');
        final myFriendsJson = jsonDecode(myFriendsFile.readAsStringSync());

        expect(myFriendsJson, {
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

        final resolverFile =
            File('${testDirectory.path}/loon/__resolver__.json');
        final resolverJson = jsonDecode(resolverFile.readAsStringSync());

        expect(resolverJson, {
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

        await Loon.clearAll();

        expect(storeFile.existsSync(), false);
        expect(myFriendsFile.existsSync(), false);
        expect(resolverFile.existsSync(), false);

        storeFile.writeAsStringSync(jsonEncode(storeJson));
        myFriendsFile.writeAsStringSync(jsonEncode(myFriendsJson));
        resolverFile.writeAsStringSync(jsonEncode(resolverJson));

        // After clearing the data and reinitializing it from disk to verify with hydration,
        // the persistor needs to be re-created so that it re-reads all data stores from disk.
        Loon.configure(persistor: TestFilePersistor());

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

          final storeFile = File('${testDirectory.path}/loon/__store__.json');
          final storeJson = jsonDecode(storeFile.readAsStringSync());

          expect(storeJson, {
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

          final userFriendsFile =
              File('${testDirectory.path}/loon/user_friends.json');
          final userFriendsJson =
              jsonDecode(userFriendsFile.readAsStringSync());

          expect(userFriendsJson, {
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

          final resolverFile =
              File('${testDirectory.path}/loon/__resolver__.json');
          final resolverJson = jsonDecode(resolverFile.readAsStringSync());

          expect(resolverJson, {
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

          await Loon.clearAll();

          storeFile.writeAsStringSync(jsonEncode(storeJson));
          userFriendsFile.writeAsStringSync(jsonEncode(userFriendsJson));
          resolverFile.writeAsStringSync(jsonEncode(resolverJson));

          // After clearing the data and reinitializing it from disk to verify with hydration,
          // the persistor needs to be recreated so that it re-reads all data stores from disk.
          Loon.configure(persistor: TestFilePersistor());

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

      test('Hydrates large persistence files', () async {
        int size = 20000;

        final store = ValueStore<Json>();
        List<TestLargeModel> models =
            List.generate(size, (_) => generateRandomModel());

        for (final model in models) {
          store.write('users__${model.id}', model.toJson());
        }

        final file = File('${testDirectory.path}/loon/users.json');
        file.writeAsStringSync(jsonEncode({
          ValueStore.root: store.inspect(),
        }));

        await Loon.hydrate();

        final largeModelCollection = Loon.collection(
          'users',
          fromJson: TestLargeModel.fromJson,
          toJson: (user) => user.toJson(),
        );

        final queryResponseSize = await logger.measure(
          'Lazy parse large collection query',
          () async {
            return largeModelCollection.get().length;
          },
        );

        // The second query should be significantly faster, since it does not need to lazily
        // parse each of the documents from their JSON representation.
        await logger.measure(
          'Already parsed collection query',
          () async {
            return largeModelCollection.get().length;
          },
        );

        expect(
          queryResponseSize,
          size,
        );
      });

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

          final file = File('${testDirectory.path}/loon/__store__.json');
          final json = jsonDecode(file.readAsStringSync());

          expect(
            json,
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

          await Loon.clearAll();

          Loon.configure(persistor: TestFilePersistor());

          file.writeAsStringSync(jsonEncode(json));

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

          final file = File('${testDirectory.path}/loon/__store__.json');
          final json = jsonDecode(file.readAsStringSync());

          expect(
            json,
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

          await Loon.clearAll();

          file.writeAsStringSync(jsonEncode(json));

          Loon.configure(persistor: TestFilePersistor());

          await Loon.hydrate([currentUserDoc]);

          expect(
            currentUserDoc.get(),
            DocumentSnapshot(
              doc: currentUserDoc,
              data: TestUserModel('Dan'),
            ),
          );

          expect(userCollection.get(), []);
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

          final file = File('${testDirectory.path}/loon/__store__.json');
          final json = jsonDecode(file.readAsStringSync());

          expect(
            json,
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

          await Loon.clearAll();

          file.writeAsStringSync(jsonEncode(json));

          Loon.configure(persistor: TestFilePersistor());

          await Loon.hydrate([Collection.root]);

          expect(
            currentUserDoc.get(),
            DocumentSnapshot(
              doc: currentUserDoc,
              data: TestUserModel('Dan'),
            ),
          );

          expect(userCollection.get(), []);
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

            final file = File('${testDirectory.path}/loon/__store__.json');

            await completer.onSync;

            expect(file.existsSync(), true);

            userCollection.delete();

            await completer.onSync;

            expect(file.existsSync(), false);
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
                key: Persistor.keyBuilder((snap) => 'users${snap.id}'),
              ),
            );

            userCollection.doc('1').create(TestUserModel('User 1'));
            userCollection.doc('2').create(TestUserModel('User 2'));
            userCollection.doc('3').create(TestUserModel('User 3'));

            final file1 = File('${testDirectory.path}/loon/users1.json');
            final file2 = File('${testDirectory.path}/loon/users2.json');
            final file3 = File('${testDirectory.path}/loon/users3.json');

            await completer.onSync;

            expect(file1.existsSync(), true);
            expect(file2.existsSync(), true);
            expect(file3.existsSync(), true);

            userCollection.delete();

            await completer.onSync;

            expect(file1.existsSync(), false);
            expect(file2.existsSync(), false);
            expect(file3.existsSync(), false);
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

            final storeFile = File('${testDirectory.path}/loon/__store__.json');
            final friendsFile = File('${testDirectory.path}/loon/friends.json');

            await completer.onSync;

            expect(storeFile.existsSync(), true);
            expect(friendsFile.existsSync(), true);

            userCollection.delete();

            await completer.onSync;

            expect(storeFile.existsSync(), false);
            expect(friendsFile.existsSync(), false);
          },
        );

        // In this scenario, multiple collections share a file data store and therefore
        // the file should not be deleted since it still has documents from another collection.
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

            final file = File('${testDirectory.path}/loon/__store__.json');

            await completer.onSync;

            Json json = jsonDecode(file.readAsStringSync());
            expect(
              json,
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

            json = jsonDecode(file.readAsStringSync());
            expect(
              json,
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
          "Deletes all file data stores",
          () async {
            final userCollection = Loon.collection(
              'users',
              fromJson: TestUserModel.fromJson,
              toJson: (user) => user.toJson(),
              persistorSettings: PersistorSettings(
                key: Persistor.key('users'),
              ),
            );

            userCollection.doc('1').create(TestUserModel('User 1'));
            userCollection.doc('2').create(TestUserModel('User 2'));

            final file = File('${testDirectory.path}/loon/users.json');
            final resolverFile =
                File('${testDirectory.path}/loon/__resolver__.json');

            await completer.onSync;

            expect(file.existsSync(), true);
            expect(resolverFile.existsSync(), true);

            await Loon.clearAll();

            expect(file.existsSync(), false);
            expect(resolverFile.existsSync(), false);
          },
        );
      },
    );

    test('Sequences operations correctly', () async {
      final List<String> operations = [];
      Loon.configure(
        persistor: TestFilePersistor(
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
}
