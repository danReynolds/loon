import 'dart:convert';
import 'dart:io';
import 'package:flutter_test/flutter_test.dart';
import 'package:loon/loon.dart';
import 'package:loon/persistor/file_persistor/file_persistor_settings.dart';
import 'models/test_file_persistor.dart';
import 'models/test_user_model.dart';
import 'utils.dart';

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
  late PersistorCompleter completer;
  late TestFilePersistor persistor;

  setUp(() {
    testDirectory = Directory.systemTemp.createTempSync('test_dir');
    final mockPathProvider = MockPathProvider();
    PathProviderPlatform.instance = mockPathProvider;

    completer = TestFilePersistor.completer = PersistorCompleter();
    persistor = TestFilePersistor(
      settings: const FilePersistorSettings(encrypted: true),
    );
  });

  tearDown(() async {
    testDirectory.deleteSync(recursive: true);
    await Loon.clearAll();
  });

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

      await completer.onPersist;

      final usersFile = File('${testDirectory.path}/loon/users.json');
      final usersJson = jsonDecode(usersFile.readAsStringSync());

      expect(usersJson, {
        "users": {
          "__values": {
            '1': {'name': 'User 1'},
          },
        },
      });

      final encryptedUsersFile =
          File('${testDirectory.path}/loon/users.encrypted.json');
      final encryptedUsersJson = jsonDecode(
        persistor.decrypt(encryptedUsersFile.readAsStringSync()),
      );

      expect(encryptedUsersJson, {
        "users": {
          "__values": {
            '2': {'name': 'User 2'},
          },
        },
      });

      final resolverFile = File('${testDirectory.path}/loon/__resolver__.json');
      final resolverJson = jsonDecode(resolverFile.readAsStringSync());

      expect(
        resolverJson,
        {
          "__refs": {
            "users": 1,
          },
          "__values": {
            "users": "users",
          }
        },
      );

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

      await completer.onPersist;

      final file = File('${testDirectory.path}/loon/users.encrypted.json');
      final json = decryptData(file.readAsStringSync());

      expect(
        json,
        {
          "users": {
            "__values": {
              "1": {'name': 'User 1'},
              "2": {'name': 'User 2'},
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

      await completer.onPersist;

      final friendsFile = File('${testDirectory.path}/loon/friends.json');
      final friendsJson = jsonDecode(friendsFile.readAsStringSync());

      expect(
        friendsJson,
        {
          "friends": {
            "__values": {
              "1": {'name': 'Friend 1'},
            }
          },
        },
      );

      final usersFile = File('${testDirectory.path}/loon/users.encrypted.json');
      final usersJson = decryptData(usersFile.readAsStringSync());

      expect(
        usersJson,
        {
          "users": {
            "__values": {
              "1": {'name': 'User 1'},
              "2": {'name': 'User 2'},
            }
          },
        },
      );
    });
  });

  test('Does not encrypt data when explicitly disabled for a collection',
      () async {
    Loon.configure(
      persistor: TestFilePersistor(
        settings: const FilePersistorSettings(encrypted: true),
      ),
    );

    final usersCollection = Loon.collection(
      'users',
      fromJson: TestUserModel.fromJson,
      toJson: (user) => user.toJson(),
      persistorSettings: const FilePersistorSettings(encrypted: false),
    );

    usersCollection.doc('1').create(TestUserModel('User 1'));
    usersCollection.doc('2').create(TestUserModel('User 2'));

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
          }
        },
      },
    );

    final encryptedFile =
        File('${testDirectory.path}/loon/users.encrypted.json');
    expect(encryptedFile.existsSync(), false);

    final resolverFile = File('${testDirectory.path}/loon/__resolver__.json');
    final resolverJson = jsonDecode(resolverFile.readAsStringSync());

    expect(
      resolverJson,
      {
        "__refs": {
          "users": 1,
        },
        "__values": {
          "users": "users",
        }
      },
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

    await completer.onPersist;

    final usersFile = File('${testDirectory.path}/loon/users.json');
    var usersJson = jsonDecode(usersFile.readAsStringSync());

    expect(
      usersJson,
      {
        "users": {
          "__values": {
            "1": {"name": "User 1"},
            "2": {"name": "User 2"},
          }
        }
      },
    );

    final resolverFile = File('${testDirectory.path}/loon/__resolver__.json');
    final resolverJson = jsonDecode(resolverFile.readAsStringSync());

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

    await completer.onPersist;

    final encryptedFile =
        File('${testDirectory.path}/loon/users.encrypted.json');
    final json = decryptData(encryptedFile.readAsStringSync());

    // The new user should have been written to an encrypted file, since the persistor was configured with encryption
    // enabled globally.
    expect(
      json,
      {
        "users": {
          "__values": {
            "3": {'name': 'User 3'},
          }
        },
      },
    );

    // The existing hydrated data should still be unencrypted, as the documents are not moved until they are updated.
    usersJson = jsonDecode(usersFile.readAsStringSync());
    expect(
      usersJson,
      {
        "users": {
          "__values": {
            "1": {"name": "User 1"},
            "2": {"name": "User 2"},
          }
        }
      },
    );

    usersCollection.doc('1').update(TestUserModel('User 1 updated'));
    usersCollection.doc('2').update(TestUserModel('User 2 updated'));

    await completer.onPersist;

    // The documents should now have been updated to exist in the encrypted users file.
    final encryptedUsersJson = decryptData(encryptedFile.readAsStringSync());

    expect(
      encryptedUsersJson,
      {
        "users": {
          "__values": {
            "1": {'name': 'User 1 updated'},
            "2": {'name': 'User 2 updated'},
            "3": {"name": "User 3"},
          },
        },
      },
    );

    // The now empty plaintext users file should have been deleted.
    expect(usersFile.existsSync(), false);
  });
}
