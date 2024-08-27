import 'dart:convert';
import 'dart:io';
import 'package:flutter_test/flutter_test.dart';
import 'package:loon/loon.dart';
import 'package:loon/persistor/file_persistor/file_persistor_settings.dart';
import '../models/test_file_persistor.dart';
import '../models/test_user_model.dart';
import '../utils.dart';

// ignore: depend_on_referenced_packages
import 'package:path_provider_platform_interface/path_provider_platform_interface.dart';
// ignore: depend_on_referenced_packages
import 'package:plugin_platform_interface/plugin_platform_interface.dart';

late Directory testDirectory;

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
  late TestFilePersistor persistor;

  setUp(() {
    testDirectory = Directory.systemTemp.createTempSync('test_dir');
    final mockPathProvider = MockPathProvider();
    PathProviderPlatform.instance = mockPathProvider;

    completer = TestFilePersistor.completer = FilePersistorCompleter();
    persistor = TestFilePersistor(
      settings: const FilePersistorSettings(encrypted: true),
    );
  });

  tearDown(() async {
    testDirectory.deleteSync(recursive: true);
    await Loon.clearAll();
  });

  group('Encrypted FilePersistor', () {
    group('hydrate', () {
      setUp(() {
        Loon.configure(persistor: persistor);
      });

      test(
          'Merges data from plaintext and encrypted persistence files into collections',
          () async {
        final userCollection = Loon.collection<TestUserModel>(
          'users',
          fromJson: TestUserModel.fromJson,
          toJson: (user) => user.toJson(),
          persistorSettings: const FilePersistorSettings(encrypted: false),
        );
        final encryptedUsersCollection = Loon.collection<TestUserModel>(
          'users',
          fromJson: TestUserModel.fromJson,
          toJson: (user) => user.toJson(),
          persistorSettings: const FilePersistorSettings(encrypted: true),
        );

        userCollection.doc('1').create(TestUserModel('User 1'));
        encryptedUsersCollection.doc('2').create(TestUserModel('User 2'));

        await completer.onSync;

        final storeFile = File('${testDirectory.path}/loon/__store__.json');
        final storeJson = jsonDecode(storeFile.readAsStringSync());

        expect(storeJson, {
          "": {
            "users": {
              "__values": {
                '1': {'name': 'User 1'},
              },
            },
          }
        });

        final encryptedStoreFile =
            File('${testDirectory.path}/loon/__store__.encrypted.json');
        final encryptedStoreJson = jsonDecode(
          persistor.decrypt(encryptedStoreFile.readAsStringSync()),
        );

        expect(encryptedStoreJson, {
          "": {
            "users": {
              "__values": {
                '2': {'name': 'User 2'},
              },
            },
          }
        });

        // Reinitialize the persistor ahead of hydration.
        Loon.configure(
          persistor: TestFilePersistor(
            settings: const FilePersistorSettings(encrypted: true),
          ),
        );

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
      });

      // This scenario takes a bit of a description. In the situation where a file for a collection is unencrypted,
// but encryption settings now specify that the collection should be encrypted, then the unencrypted file should
// be hydrated into memory, but any subsequent persistence calls for that collection should move the updated data
// from the unencrypted data store to the encrypted data store. Once all the data has been moved, the unencrypted
// file should be deleted.
      test('Encrypts collections hydrated from unencrypted files', () async {
        Loon.configure(persistor: TestFilePersistor());

        final usersCollection = Loon.collection(
          'users',
          fromJson: TestUserModel.fromJson,
          toJson: (user) => user.toJson(),
        );

        usersCollection.doc('1').create(TestUserModel('User 1'));
        usersCollection.doc('2').create(TestUserModel('User 2'));

        await completer.onSync;

        final storeFile = File('${testDirectory.path}/loon/__store__.json');
        var storeJson = jsonDecode(storeFile.readAsStringSync());

        expect(
          storeJson,
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

        Loon.configure(
          persistor: TestFilePersistor(
            settings: const FilePersistorSettings(encrypted: true),
          ),
        );

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

        final encryptedStoreFile =
            File('${testDirectory.path}/loon/__store__.encrypted.json');
        var encryptedStoreJson =
            decryptData(encryptedStoreFile.readAsStringSync());

        // The new user should have been written to an encrypted root file, since the persistor was configured with encryption
        // enabled globally.
        expect(
          encryptedStoreJson,
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
        storeJson = jsonDecode(storeFile.readAsStringSync());
        expect(
          storeJson,
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

        // The documents should now have been updated to exist in the encrypted root file.
        encryptedStoreJson = decryptData(encryptedStoreFile.readAsStringSync());

        expect(
          encryptedStoreJson,
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

        // The now empty plaintext root file should have been deleted.
        expect(storeFile.existsSync(), false);
      });
    });

    group('persist', () {
      test('Encrypts data when enabled globally for all collections', () async {
        Loon.configure(
          persistor: TestFilePersistor(
            settings: const FilePersistorSettings(encrypted: true),
          ),
        );

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

        final file =
            File('${testDirectory.path}/loon/__store__.encrypted.json');
        final json = decryptData(file.readAsStringSync());

        expect(
          json,
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

      test('Encrypts data when explicitly enabled for a collection', () async {
        Loon.configure(
          persistor: TestFilePersistor(
            settings: const FilePersistorSettings(encrypted: false),
          ),
        );

        final friendsCollection = Loon.collection<TestUserModel>(
          'friends',
          fromJson: TestUserModel.fromJson,
          toJson: (user) => user.toJson(),
        );

        final usersCollection = Loon.collection<TestUserModel>(
          'users',
          fromJson: TestUserModel.fromJson,
          toJson: (user) => user.toJson(),
          persistorSettings: const FilePersistorSettings(encrypted: true),
        );

        friendsCollection.doc('1').create(TestUserModel('Friend 1'));
        usersCollection.doc('1').create(TestUserModel('User 1'));
        usersCollection.doc('2').create(TestUserModel('User 2'));

        await completer.onSync;

        final file = File('${testDirectory.path}/loon/__store__.json');
        final json = jsonDecode(file.readAsStringSync());

        expect(
          json,
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

        final encryptedFile =
            File('${testDirectory.path}/loon/__store__.encrypted.json');
        final encryptedJson = decryptData(encryptedFile.readAsStringSync());

        expect(
          encryptedJson,
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
        Loon.configure(
          persistor: TestFilePersistor(
            settings: const FilePersistorSettings(encrypted: false),
          ),
        );

        final usersCollection = Loon.collection<TestUserModel>(
          'users',
          fromJson: TestUserModel.fromJson,
          toJson: (user) => user.toJson(),
          persistorSettings: const FilePersistorSettings(encrypted: true),
        );

        final user1FriendsCollection = usersCollection.doc('1').subcollection(
              'friends',
              fromJson: TestUserModel.fromJson,
              toJson: (friend) => friend.toJson(),
            );

        usersCollection.doc('1').create(TestUserModel('User 1'));
        usersCollection.doc('2').create(TestUserModel('User 2'));
        user1FriendsCollection.doc('1').create(TestUserModel('Friend 1'));

        await completer.onSync;

        final file = File('${testDirectory.path}/loon/__store__.json');
        expect(file.existsSync(), false);

        final encryptedFile =
            File('${testDirectory.path}/loon/__store__.encrypted.json');
        final encryptedJson = decryptData(encryptedFile.readAsStringSync());

        expect(
          encryptedJson,
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

      test('Subcollections can override parent encryption settings', () async {
        Loon.configure(
          persistor: TestFilePersistor(
            settings: const FilePersistorSettings(encrypted: false),
          ),
        );

        final usersCollection = Loon.collection<TestUserModel>(
          'users',
          fromJson: TestUserModel.fromJson,
          toJson: (user) => user.toJson(),
          persistorSettings: const FilePersistorSettings(encrypted: true),
        );

        final user1FriendsCollection = usersCollection.doc('1').subcollection(
              'friends',
              fromJson: TestUserModel.fromJson,
              toJson: (friend) => friend.toJson(),
              persistorSettings: const FilePersistorSettings(encrypted: false),
            );

        usersCollection.doc('1').create(TestUserModel('User 1'));
        usersCollection.doc('2').create(TestUserModel('User 2'));
        user1FriendsCollection.doc('1').create(TestUserModel('Friend 1'));

        await completer.onSync;

        final file = File('${testDirectory.path}/loon/__store__.json');
        final fileJson = jsonDecode(file.readAsStringSync());

        expect(
          fileJson,
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

        final encryptedFile =
            File('${testDirectory.path}/loon/__store__.encrypted.json');
        final encryptedJson = decryptData(encryptedFile.readAsStringSync());

        expect(
          encryptedJson,
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

      test('Does not encrypt data when explicitly disabled for a collection',
          () async {
        Loon.configure(
          persistor: TestFilePersistor(
            settings: const FilePersistorSettings(encrypted: true),
          ),
        );

        final usersCollection = Loon.collection<TestUserModel>(
          'users',
          fromJson: TestUserModel.fromJson,
          toJson: (user) => user.toJson(),
          persistorSettings: const FilePersistorSettings(encrypted: false),
        );

        usersCollection.doc('1').create(TestUserModel('User 1'));
        usersCollection.doc('2').create(TestUserModel('User 2'));

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
                }
              },
            }
          },
        );

        final encryptedFile =
            File('${testDirectory.path}/loon/__store__.encrypted.json');
        expect(encryptedFile.existsSync(), false);
      });
    });
  });
}
