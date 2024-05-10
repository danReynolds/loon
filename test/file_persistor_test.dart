import 'dart:convert';
import 'dart:io';
import 'package:flutter_test/flutter_test.dart';
import 'package:loon/loon.dart';
import 'package:loon/persistor/file_persistor/file_persistor_settings.dart';

// ignore: depend_on_referenced_packages
import 'package:path_provider_platform_interface/path_provider_platform_interface.dart';
// ignore: depend_on_referenced_packages
import 'package:plugin_platform_interface/plugin_platform_interface.dart';

import 'models/test_file_persistor.dart';
import 'models/test_large_model.dart';
import 'models/test_user_model.dart';
import 'utils.dart';

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
  var completer = TestFilePersistor.completer = PersistorCompleter();

  setUp(() {
    completer = TestFilePersistor.completer = PersistorCompleter();
    testDirectory = Directory.systemTemp.createTempSync('test_dir');
    final mockPathProvider = MockPathProvider();
    PathProviderPlatform.instance = mockPathProvider;

    Loon.configure(persistor: TestFilePersistor());
  });

  tearDown(() async {
    testDirectory.deleteSync(recursive: true);
    await Loon.clearAll();
  });

  group(
    'persist',
    () {
      test(
        'Persists new documents in their top-level collection by default',
        () async {
          final userCollection = Loon.collection(
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

          await completer.onPersist;

          final file = File('${testDirectory.path}/loon/users.json');
          final json = jsonDecode(file.readAsStringSync());

          expect(
            json,
            {
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
            },
          );

          final resolverFile =
              File('${testDirectory.path}/loon/__resolver__.json');
          final resolverJson = jsonDecode(resolverFile.readAsStringSync());

          expect(
            resolverJson,
            {
              "__values": {
                "users": "users",
              },
              "__refs": {
                "users": 1,
              },
            },
          );
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

          await completer.onPersist;

          userCollection.doc('2').update(TestUserModel('User 2 updated'));

          await completer.onPersist;

          final file = File('${testDirectory.path}/loon/users.json');
          final json = jsonDecode(file.readAsStringSync());

          expect(
            json,
            {
              "users": {
                "__values": {
                  "1": {'name': 'User 1'},
                  "2": {'name': 'User 2 updated'},
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
              "__values": {
                "users": "users",
              },
              "__refs": {
                "users": 1,
              },
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

          await completer.onPersist;

          userCollection.doc('2').delete();

          await completer.onPersist;

          final file = File('${testDirectory.path}/loon/users.json');
          final json = jsonDecode(file.readAsStringSync());

          expect(
            json,
            {
              "users": {
                "__values": {
                  "1": {"name": "User 1"}
                },
              }
            },
          );

          final resolverFile =
              File('${testDirectory.path}/loon/__resolver__.json');
          final resolverJson = jsonDecode(resolverFile.readAsStringSync());

          expect(
            resolverJson,
            {
              "__values": {
                "users": "users",
              },
              "__refs": {
                "users": 1,
              },
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

          final file = File('${testDirectory.path}/loon/users.json');

          await completer.onPersist;

          expect(file.existsSync(), true);

          // If all documents of a file are deleted, the file itself should be deleted.
          userCollection.doc('1').delete();
          userCollection.doc('2').delete();

          await completer.onPersist;

          expect(file.existsSync(), false);
        },
      );

      test(
        'Persists documents using a document-level key',
        () async {
          final userCollection = Loon.collection<TestUserModel>(
            'users',
            fromJson: TestUserModel.fromJson,
            toJson: (user) => user.toJson(),
            persistorSettings: FilePersistorSettings(
              key: FilePersistor.keyBuilder((snap) {
                if (snap.id == '1') {
                  return 'users';
                }
                return 'other_users';
              }),
            ),
          );

          userCollection.doc('1').create(TestUserModel('User 1'));
          userCollection.doc('2').create(TestUserModel('User 2'));

          await completer.onPersist;

          final usersFile = File('${testDirectory.path}/loon/users.json');
          final otherUsersFile =
              File('${testDirectory.path}/loon/other_users.json');
          final usersJson = jsonDecode(usersFile.readAsStringSync());
          final otherUsersJson = jsonDecode(otherUsersFile.readAsStringSync());

          expect(
            usersJson,
            {
              "users": {
                "__values": {
                  "1": {'name': 'User 1'},
                },
              }
            },
          );

          expect(
            otherUsersJson,
            {
              "users": {
                "__values": {
                  "2": {'name': 'User 2'},
                },
              }
            },
          );

          final resolverFile =
              File('${testDirectory.path}/loon/__resolver__.json');
          final resolverJson = jsonDecode(resolverFile.readAsStringSync());

          expect(
            resolverJson,
            {
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
        },
      );

      test(
        'Persists documents using a collection-level key',
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
                // Aggregate all the `friends` subcollections of users into the `friends` data store.
                persistorSettings:
                    FilePersistorSettings(key: FilePersistor.key('friends')),
              )
              .doc('1')
              .create(user);

          await completer.onPersist;

          final usersFile = File('${testDirectory.path}/loon/users.json');
          final friendsFile = File('${testDirectory.path}/loon/friends.json');
          final usersJson = jsonDecode(usersFile.readAsStringSync());
          final friendsJson = jsonDecode(friendsFile.readAsStringSync());

          expect(
            usersJson,
            {
              "users": {
                "__values": {
                  "1": {'name': 'User 1'},
                  "2": {'name': 'User 2'},
                },
              }
            },
          );

          expect(
            friendsJson,
            {
              "users": {
                "2": {
                  "friends": {
                    "__values": {
                      "1": {'name': 'User 1'},
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
              "__values": {
                "users": "users",
              },
              "__refs": {
                "users": 1,
              },
              "users": {
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
        },
      );

      // The following group of tests cover the valid scenarios where a persistence key for a value changes:
      // 1. null -> document-level key
      // 2. null -> collection-level key
      // 3. document-level key -> null
      // 4. document-level key -> updated document-level key
      // 5. document-level key -> collection-level key
      // 6. collection-level key -> updated collection-level key
      group(
        'Persistence key changes',
        () {
          group(
            '1. null -> document-level key',
            () {
              test(
                'Moves the document and its subcollections in the default store to the store specified by its document-level key',
                () async {
                  final usersCollection = Loon.collection<TestUserModel>(
                    'users',
                    fromJson: TestUserModel.fromJson,
                    toJson: (user) => user.toJson(),
                  );

                  final updatedUsersCollection = Loon.collection<TestUserModel>(
                    'users',
                    fromJson: TestUserModel.fromJson,
                    toJson: (user) => user.toJson(),
                    persistorSettings: FilePersistorSettings(
                      key: FilePersistor.keyBuilder(
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

                  await completer.onPersist;

                  final usersFile =
                      File('${testDirectory.path}/loon/users.json');
                  var usersJson = jsonDecode(usersFile.readAsStringSync());

                  expect(
                    usersJson,
                    {
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
                        "users": 1,
                      },
                      "__values": {
                        "users": "users",
                      },
                    },
                  );

                  updatedUsersCollection
                      .doc('1')
                      .update(TestUserModel('User 1 updated'));

                  await completer.onPersist;

                  usersJson = jsonDecode(usersFile.readAsStringSync());
                  expect(
                    usersJson,
                    {
                      "users": {
                        "__values": {
                          "2": {"name": "User 2"},
                        },
                      }
                    },
                  );

                  final users1File =
                      File('${testDirectory.path}/loon/users_1.json');
                  var users1Json = jsonDecode(users1File.readAsStringSync());

                  expect(
                    users1Json,
                    {
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
                    },
                  );

                  resolverJson = jsonDecode(resolverFile.readAsStringSync());
                  expect(
                    resolverJson,
                    {
                      "__refs": {
                        "users": 1,
                      },
                      "__values": {
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
            '2. null -> collection-level key',
            () {
              test(
                'Moves all documents and their subcollections in the default store to the store specified by the collection-level key',
                () async {
                  final usersCollection = Loon.collection<TestUserModel>(
                    'users',
                    fromJson: TestUserModel.fromJson,
                    toJson: (user) => user.toJson(),
                  );

                  final updatedUsersCollection = Loon.collection<TestUserModel>(
                    'users',
                    fromJson: TestUserModel.fromJson,
                    toJson: (user) => user.toJson(),
                    persistorSettings: FilePersistorSettings(
                      key: FilePersistor.key('other_users'),
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

                  await completer.onPersist;

                  final usersFile =
                      File('${testDirectory.path}/loon/users.json');
                  var usersJson = jsonDecode(usersFile.readAsStringSync());

                  expect(
                    usersJson,
                    {
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
                        "users": 1,
                      },
                      "__values": {
                        "users": "users",
                      },
                    },
                  );

                  updatedUsersCollection
                      .doc('1')
                      .update(TestUserModel('User 1 updated'));

                  await completer.onPersist;

                  expect(usersFile.existsSync(), false);

                  final otherUsersFile =
                      File('${testDirectory.path}/loon/other_users.json');
                  var otherUsersJson =
                      jsonDecode(otherUsersFile.readAsStringSync());

                  expect(
                    otherUsersJson,
                    {
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
                    },
                  );

                  resolverJson = jsonDecode(resolverFile.readAsStringSync());
                  expect(
                    resolverJson,
                    {
                      "__refs": {
                        "other_users": 1,
                      },
                      "__values": {
                        "users": "other_users",
                      },
                    },
                  );
                },
              );
            },
          );

          group(
            '3. document-level key -> null',
            () {
              test(
                'Moves the document and its subcollections in the previous document store to the default store',
                () async {
                  final documentKeyUsersCollection =
                      Loon.collection<TestUserModel>(
                    'users',
                    fromJson: TestUserModel.fromJson,
                    toJson: (user) => user.toJson(),
                    persistorSettings: FilePersistorSettings(
                      key: FilePersistor.keyBuilder(
                        (snap) => "users_${snap.id}",
                      ),
                    ),
                  );
                  final usersCollection = Loon.collection<TestUserModel>(
                    'users',
                    fromJson: TestUserModel.fromJson,
                    toJson: (user) => user.toJson(),
                  );

                  documentKeyUsersCollection
                      .doc('1')
                      .create(TestUserModel('User 1'));
                  documentKeyUsersCollection
                      .doc('2')
                      .create(TestUserModel('User 2'));
                  documentKeyUsersCollection
                      .doc('1')
                      .subcollection(
                        'friends',
                        fromJson: TestUserModel.fromJson,
                        toJson: (user) => user.toJson(),
                      )
                      .doc('1')
                      .create(TestUserModel('Friend 1'));

                  await completer.onPersist;

                  final users1File =
                      File('${testDirectory.path}/loon/users_1.json');
                  var users1Json = jsonDecode(users1File.readAsStringSync());

                  expect(
                    users1Json,
                    {
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
                    },
                  );

                  final users2File =
                      File('${testDirectory.path}/loon/users_2.json');
                  var users2Json = jsonDecode(users2File.readAsStringSync());

                  expect(
                    users2Json,
                    {
                      "users": {
                        "__values": {
                          "2": {"name": "User 2"},
                        },
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

                  await completer.onPersist;

                  final usersFile =
                      File('${testDirectory.path}/loon/users.json');
                  var usersJson = jsonDecode(usersFile.readAsStringSync());

                  expect(
                    usersJson,
                    {
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
                    },
                  );

                  expect(users1File.existsSync(), false);

                  users2Json = jsonDecode(users2File.readAsStringSync());
                  expect(
                    users2Json,
                    {
                      "users": {
                        "__values": {
                          "2": {"name": "User 2"},
                        },
                      }
                    },
                  );

                  resolverJson = jsonDecode(resolverFile.readAsStringSync());
                  expect(
                    resolverJson,
                    {
                      "__refs": {
                        "users": 1,
                      },
                      "__values": {
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

          group(
            '4. document-level key -> updated document-level key',
            () {
              test(
                'Moves the document and its subcollections from the previous store to the store specified by its updated document-level key',
                () async {
                  final userCollection = Loon.collection<TestUserModel>(
                    'users',
                    fromJson: TestUserModel.fromJson,
                    toJson: (user) => user.toJson(),
                    persistorSettings: FilePersistorSettings(
                      key: FilePersistor.keyBuilder<TestUserModel>(
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

                  await completer.onPersist;

                  final usersFile =
                      File('${testDirectory.path}/loon/users.json');
                  var usersJson = jsonDecode(usersFile.readAsStringSync());

                  expect(
                    usersJson,
                    {
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
                      }
                    },
                  );

                  userCollection
                      .doc('2')
                      .update(TestUserModel('User 2 updated'));

                  await completer.onPersist;

                  usersJson = jsonDecode(usersFile.readAsStringSync());
                  expect(
                    usersJson,
                    {
                      "users": {
                        "__values": {
                          "1": {"name": "User 1"},
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
                    },
                  );

                  final resolverFile =
                      File('${testDirectory.path}/loon/__resolver__.json');
                  final resolverJson =
                      jsonDecode(resolverFile.readAsStringSync());

                  expect(
                    resolverJson,
                    {
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
            '5. document-level key -> collection-level key',
            () {
              test(
                'Moves the document, its subcollections, and any other documents in the previous default document store, to the store specified by its collection key',
                () async {
                  final usersCollection = Loon.collection<TestUserModel>(
                    'users',
                    fromJson: TestUserModel.fromJson,
                    toJson: (user) => user.toJson(),
                  );

                  final documentKeyUsersCollection =
                      Loon.collection<TestUserModel>(
                    'users',
                    fromJson: TestUserModel.fromJson,
                    toJson: (user) => user.toJson(),
                    persistorSettings: FilePersistorSettings(
                      key: FilePersistor.keyBuilder(
                        (snap) => "users_${snap.id}",
                      ),
                    ),
                  );

                  final otherUsersCollection = Loon.collection<TestUserModel>(
                    'users',
                    fromJson: TestUserModel.fromJson,
                    toJson: (user) => user.toJson(),
                    persistorSettings: FilePersistorSettings(
                      key: FilePersistor.key('other_users'),
                    ),
                  );

                  documentKeyUsersCollection
                      .doc('1')
                      .create(TestUserModel('User 1'));
                  documentKeyUsersCollection
                      .doc('2')
                      .create(TestUserModel('User 2'));
                  documentKeyUsersCollection
                      .doc('1')
                      .subcollection(
                        'friends',
                        fromJson: TestUserModel.fromJson,
                        toJson: (user) => user.toJson(),
                      )
                      .doc('1')
                      .create(TestUserModel('Friend 1'));
                  usersCollection.doc('3').create(TestUserModel('User 3'));

                  await completer.onPersist;

                  final usersFile =
                      File('${testDirectory.path}/loon/users.json');
                  var usersJson = jsonDecode(usersFile.readAsStringSync());

                  expect(usersJson, {
                    "users": {
                      "__values": {
                        "3": {"name": "User 3"},
                      },
                    }
                  });

                  final users1File =
                      File('${testDirectory.path}/loon/users_1.json');
                  var users1Json = jsonDecode(users1File.readAsStringSync());

                  expect(
                    users1Json,
                    {
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
                    },
                  );

                  final users2File =
                      File('${testDirectory.path}/loon/users_2.json');
                  var users2Json = jsonDecode(users2File.readAsStringSync());

                  expect(
                    users2Json,
                    {
                      "users": {
                        "__values": {
                          "2": {"name": "User 2"},
                        },
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
                        "users": 1,
                      },
                      "__values": {
                        "users": "users",
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

                  otherUsersCollection
                      .doc('1')
                      .update(TestUserModel('User 1 updated'));

                  await completer.onPersist;

                  final otherUsersFile =
                      File('${testDirectory.path}/loon/other_users.json');
                  var otherUsersJson =
                      jsonDecode(otherUsersFile.readAsStringSync());

                  expect(
                    otherUsersJson,
                    {
                      "users": {
                        "__values": {
                          "1": {"name": "User 1 updated"},
                          "3": {"name": "User 3"},
                        },
                        "1": {
                          "friends": {
                            "__values": {
                              "1": {"name": "Friend 1"},
                            }
                          }
                        }
                      }
                    },
                  );

                  expect(usersFile.existsSync(), false);
                  expect(users1File.existsSync(), false);

                  users2Json = jsonDecode(users2File.readAsStringSync());
                  expect(
                    users2Json,
                    {
                      "users": {
                        "__values": {
                          "2": {"name": "User 2"},
                        },
                      }
                    },
                  );

                  resolverJson = jsonDecode(resolverFile.readAsStringSync());
                  expect(
                    resolverJson,
                    {
                      "__refs": {
                        "other_users": 1,
                      },
                      "__values": {
                        "users": "other_users",
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
    },
  );

  group('hydrate', () {
    test('Hydrates all data from persistence files', () async {
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
                    FilePersistorSettings(key: FilePersistor.key('my_friends')),
              );

      userCollection.doc('1').create(TestUserModel('User 1'));
      userCollection.doc('2').create(TestUserModel('User 2'));

      friendsCollection.doc('1').create(TestUserModel('Friend 1'));
      friendsCollection.doc('2').create(TestUserModel('Friend 2'));

      userFriendsCollection.doc('3').create(TestUserModel('Friend 3'));

      await completer.onPersist;

      final usersFile = File('${testDirectory.path}/loon/users.json');
      final usersJson = jsonDecode(usersFile.readAsStringSync());

      expect(usersJson, {
        "users": {
          "__values": {
            "1": {"name": "User 1"},
            "2": {"name": "User 2"},
          }
        }
      });

      final friendsFile = File('${testDirectory.path}/loon/friends.json');
      final friendsJson = jsonDecode(friendsFile.readAsStringSync());

      expect(friendsJson, {
        "friends": {
          "__values": {
            "1": {"name": "Friend 1"},
            "2": {"name": "Friend 2"},
          }
        }
      });

      final myFriendsFile = File('${testDirectory.path}/loon/my_friends.json');
      final myFriendsJson = jsonDecode(myFriendsFile.readAsStringSync());

      expect(myFriendsJson, {
        "users": {
          "1": {
            "friends": {
              "__values": {
                "3": {"name": "Friend 3"},
              }
            }
          }
        }
      });

      final resolverFile = File('${testDirectory.path}/loon/__resolver__.json');
      final resolverJson = jsonDecode(resolverFile.readAsStringSync());

      expect(resolverJson, {
        "__refs": {
          "users": 1,
          "friends": 1,
        },
        "__values": {
          "users": "users",
          "friends": "friends",
        },
        "users": {
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

      expect(usersFile.existsSync(), false);
      expect(friendsFile.existsSync(), false);
      expect(myFriendsFile.existsSync(), false);
      expect(resolverFile.existsSync(), false);

      usersFile.writeAsStringSync(jsonEncode(usersJson));
      myFriendsFile.writeAsStringSync(jsonEncode(myFriendsJson));
      friendsFile.writeAsStringSync(jsonEncode(friendsJson));

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
    });

    test(
      "Hydrates all data under the given path from persistence files",
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

        final userFriendsCollection = Loon.collection('users')
            .doc('1')
            .subcollection<TestUserModel>(
              'friends',
              fromJson: TestUserModel.fromJson,
              toJson: (user) => user.toJson(),
              persistorSettings:
                  FilePersistorSettings(key: FilePersistor.key('my_friends')),
            );

        userCollection.doc('1').create(TestUserModel('User 1'));
        userCollection.doc('2').create(TestUserModel('User 2'));

        friendsCollection.doc('1').create(TestUserModel('Friend 1'));
        friendsCollection.doc('2').create(TestUserModel('Friend 2'));

        userFriendsCollection.doc('3').create(TestUserModel('Friend 3'));

        await completer.onPersist;

        final usersFile = File('${testDirectory.path}/loon/users.json');
        final usersJson = jsonDecode(usersFile.readAsStringSync());

        final friendsFile = File('${testDirectory.path}/loon/friends.json');
        final friendsJson = jsonDecode(friendsFile.readAsStringSync());

        final myFriendsFile =
            File('${testDirectory.path}/loon/my_friends.json');
        final myFriendsJson = jsonDecode(myFriendsFile.readAsStringSync());

        final resolverFile =
            File('${testDirectory.path}/loon/__resolver__.json');
        final resolverJson = jsonDecode(resolverFile.readAsStringSync());

        await Loon.clearAll();

        usersFile.writeAsStringSync(jsonEncode(usersJson));
        myFriendsFile.writeAsStringSync(jsonEncode(myFriendsJson));
        friendsFile.writeAsStringSync(jsonEncode(friendsJson));
        resolverFile.writeAsStringSync(jsonEncode(resolverJson));

        // After clearing the data and reinitializing it from disk to verify with hydration,
        // the persistor needs to be re-created so that it re-reads all data stores from disk.
        Loon.configure(persistor: TestFilePersistor());

        await Loon.hydrate([userCollection]);

        // Only the user collection and its subcollections should have been hydrated.
        // The `friends` collection should remain empty, while `users` and `users__1__friends`
        // should be been hydrated from persistence.

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
      },
    );

    // In this scenario, the document `users__1` was persisted to other_users.json in a previous session,
    // but now before hydration it has been re-persisted to users.json. The subsequent hydration of other_users.json
    // should favor the current value in the store over the hydrated value, and remove the stale persisted value from
    // the other_users.json file store.
    test('Correctly merges data from a stale file store', () async {
      // The file to be hydrated needs to be created before the persistor is initialized
      // so that the persistor discovers the file data store as part of its initialization.
      final file = File('${testDirectory.path}/loon/other_users.json');
      file.writeAsStringSync(
        jsonEncode(
          {
            "users": {
              "__values": {
                "1": {
                  "name": "User 1",
                },
                "2": {
                  "name": "User 2",
                }
              }
            }
          },
        ),
      );

      Loon.configure(persistor: TestFilePersistor());

      final userCollection = Loon.collection(
        'users',
        fromJson: TestUserModel.fromJson,
        toJson: (user) => user.toJson(),
      );

      userCollection.doc('1').create(TestUserModel('User 1 latest'));

      await completer.onPersist;

      await Loon.hydrate();

      expect(
        userCollection.get(),
        [
          DocumentSnapshot(
            doc: userCollection.doc('1'),
            data: TestUserModel('User 1 latest'),
          ),
          DocumentSnapshot(
            doc: userCollection.doc('2'),
            data: TestUserModel('User 2'),
          ),
        ],
      );

      // The other_users file data store should have moved its data to the users data store, since the resolver
      // points the users collection to the users file data store.
      //
      // In order to verify this, we need to trigger another persist since the hydration just makes this data
      // migration from stale data stores in memory and delays writing the change until the next persist event
      // to make hydration faster.
      userCollection.doc('3').create(TestUserModel('User 3'));

      await completer.onPersist;

      final resolverFile = File('${testDirectory.path}/loon/__resolver__.json');
      final resolverJson = jsonDecode(resolverFile.readAsStringSync());

      expect(
        resolverJson,
        {
          "__values": {
            "users": "users",
          },
          "__refs": {
            "users": 1,
          },
        },
      );

      final usersFile = File('${testDirectory.path}/loon/users.json');
      final usersJson = jsonDecode(usersFile.readAsStringSync());

      expect(usersJson, {
        "users": {
          "__values": {
            "1": {"name": "User 1 latest"},
            "2": {"name": "User 2"},
            "3": {"name": "User 3"},
          },
        },
      });

      // Since all the data has been moved from the other_users data store to the users data store,
      // the other_users store should have been removed.
      final otherUsersFile =
          File('${testDirectory.path}/loon/other_users.json');
      expect(otherUsersFile.existsSync(), false);
    });

    test('Hydrates large persistence files', () async {
      int size = 20000;

      final store = IndexedValueStore<Json>();
      List<TestLargeModel> models =
          List.generate(size, (_) => generateRandomModel());

      for (final model in models) {
        store.write('users__${model.id}', model.toJson());
      }

      final file = File('${testDirectory.path}/loon/users.json');
      file.writeAsStringSync(jsonEncode(store.inspect()));

      final resolverFile = File('${testDirectory.path}/loon/__resolver__.json');
      resolverFile.writeAsStringSync(jsonEncode(
        {
          "__refs": {
            "users": 1,
          },
          "__values": {
            "users": "users",
          },
        },
      ));

      await Loon.hydrate();

      final largeModelCollection = Loon.collection(
        'users',
        fromJson: TestLargeModel.fromJson,
        toJson: (user) => user.toJson(),
      );

      final collectionSize = await logger.measure(
        'Large collection query',
        () async {
          return largeModelCollection.get().length;
        },
      );

      expect(
        collectionSize,
        size,
      );
    });
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

          final file = File('${testDirectory.path}/loon/users.json');

          await completer.onPersist;

          expect(file.existsSync(), true);

          userCollection.delete();

          await completer.onClear;

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
            persistorSettings: FilePersistorSettings(
              key: FilePersistor.keyBuilder((snap) => 'users${snap.id}'),
            ),
          );

          userCollection.doc('1').create(TestUserModel('User 1'));
          userCollection.doc('2').create(TestUserModel('User 2'));
          userCollection.doc('3').create(TestUserModel('User 3'));

          final file1 = File('${testDirectory.path}/loon/users1.json');
          final file2 = File('${testDirectory.path}/loon/users2.json');
          final file3 = File('${testDirectory.path}/loon/users3.json');

          await completer.onPersist;

          expect(file1.existsSync(), true);
          expect(file2.existsSync(), true);
          expect(file3.existsSync(), true);

          userCollection.delete();

          await completer.onClear;

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
                persistorSettings: FilePersistorSettings(
                  key: FilePersistor.key('friends'),
                ),
              );

          userCollection.doc('1').create(TestUserModel('User 1'));
          userCollection.doc('2').create(TestUserModel('User 2'));
          friendsCollection.doc('1').create(TestUserModel('Friend 1'));

          final userFile = File('${testDirectory.path}/loon/users.json');
          final friendsFile = File('${testDirectory.path}/loon/friends.json');

          await completer.onPersist;

          expect(userFile.existsSync(), true);
          expect(friendsFile.existsSync(), true);

          userCollection.delete();

          await completer.onClear;

          expect(userFile.existsSync(), false);
          expect(friendsFile.existsSync(), false);
        },
      );

      // In this scenario, multiple collections share a file data store and therefore
      // the file should not be deleted since it still has documents from another collection.
      test(
        'Retains data stores that share collections',
        () async {
          final userCollection = Loon.collection(
            'users',
            fromJson: TestUserModel.fromJson,
            toJson: (user) => user.toJson(),
            persistorSettings: FilePersistorSettings(
              key: FilePersistor.key('shared'),
            ),
          );
          final friendsCollection = Loon.collection<TestUserModel>(
            'friends',
            fromJson: TestUserModel.fromJson,
            toJson: (user) => user.toJson(),
            persistorSettings: FilePersistorSettings(
              key: FilePersistor.key('shared'),
            ),
          );

          userCollection.doc('1').create(TestUserModel('User 1'));
          userCollection.doc('2').create(TestUserModel('User 2'));
          friendsCollection.doc('1').create(TestUserModel('Friend 1'));
          friendsCollection.doc('2').create(TestUserModel('Friend 2'));

          final file = File('${testDirectory.path}/loon/shared.json');

          await completer.onPersist;

          Json json = jsonDecode(file.readAsStringSync());
          expect(
            json,
            {
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
            },
          );

          userCollection.delete();

          await completer.onClear;

          json = jsonDecode(file.readAsStringSync());
          expect(
            json,
            {
              "friends": {
                "__values": {
                  "1": {'name': 'Friend 1'},
                  "2": {'name': 'Friend 2'},
                },
              },
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
          );

          userCollection.doc('1').create(TestUserModel('User 1'));
          userCollection.doc('2').create(TestUserModel('User 2'));

          final file = File('${testDirectory.path}/loon/users.json');
          final resolverFile =
              File('${testDirectory.path}/loon/__resolver__.json');

          await completer.onPersist;

          expect(file.existsSync(), true);
          expect(resolverFile.existsSync(), true);

          await Loon.clearAll();

          expect(file.existsSync(), false);
          expect(resolverFile.existsSync(), false);
        },
      );
    },
  );
}
