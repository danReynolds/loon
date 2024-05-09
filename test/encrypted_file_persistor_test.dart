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
  var completer = TestFilePersistor.completer = PersistorCompleter();

  setUp(() {
    completer = TestFilePersistor.completer = PersistorCompleter();
    testDirectory = Directory.systemTemp.createTempSync('test_dir');
    final mockPathProvider = MockPathProvider();
    PathProviderPlatform.instance = mockPathProvider;
  });

  tearDown(() async {
    testDirectory.deleteSync(recursive: true);
    await Loon.clearAll();
  });

  group('hydrate', () {
    setUp(() {
      Loon.configure(
        persistor: TestFilePersistor(
          settings: const FilePersistorSettings(encrypted: true),
        ),
      );
    });

    test('Hydrates data from encrypted persistence files into collections',
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
      final encryptedUsersJson =
          jsonDecode(encryptedUsersFile.readAsStringSync());

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
            "users.encrypted": 1,
          },
          "__values": {
            "users": "users",
            "users.encrypted": "users.encrypted",
          }
        },
      );

      // await Loon.hydrate();

      // expect(
      //   userCollection.get(),
      //   [
      //     DocumentSnapshot(
      //       doc: userCollection.doc('1'),
      //       data: TestUserModel('User 1'),
      //     ),
      //     DocumentSnapshot(
      //       doc: userCollection.doc('2'),
      //       data: TestUserModel('User 2'),
      //     ),
      //     DocumentSnapshot(
      //       doc: userCollection.doc('3'),
      //       data: TestUserModel('User 3'),
      //     ),
      //   ],
      // );

      // final resolverFile = File('${testDirectory.path}/loon/__resolver__.json');
      // final resolverJson = jsonDecode(resolverFile.readAsStringSync());

      // expect(resolverJson, {
      //   "__refs": {
      //     "users.encrypted": 1,
      //   },
      //   "__values": {
      //     "users.encrypted": "users.encrypted",
      //   }
      // });
    });

    test(
        'Merges hydrated data from encrypted and non-encrypted persistence files into collection',
        () async {
      Directory('${testDirectory.path}/loon').createSync();
      final plaintextFile = File('${testDirectory.path}/loon/users.json');

      plaintextFile.writeAsStringSync(
        jsonEncode({
          "users": {
            "__values": {
              "2": {'name': 'User 2'},
              "3": {'name': 'User 3'},
            }
          }
        }),
      );

      final encryptedFile =
          File('${testDirectory.path}/loon/users.encrypted.json');

      encryptedFile.writeAsStringSync(
        encryptData({
          "users": {
            "__values": {
              "4": {'name': 'User 4'},
            },
          }
        }),
      );

      final userCollection = Loon.collection(
        'users',
        fromJson: TestUserModel.fromJson,
        toJson: (user) => user.toJson(),
      );

      userCollection.doc('1').create(TestUserModel('User 1'));

      await completer.onPersist;

      await Loon.hydrate();

      expect(
        userCollection.get(),
        unorderedEquals([
          DocumentSnapshot(
            doc: userCollection.doc('1'),
            data: TestUserModel('User 1'),
          ),
          DocumentSnapshot(
            doc: userCollection.doc('2'),
            data: TestUserModel('User 2'),
          ),
          DocumentSnapshot(
            doc: userCollection.doc('3'),
            data: TestUserModel('User 3'),
          ),
          DocumentSnapshot(
            doc: userCollection.doc('4'),
            data: TestUserModel('User 4'),
          ),
        ]),
      );

      final resolverFile = File('${testDirectory.path}/loon/__resolver__.json');
      final resolverJson = jsonDecode(resolverFile.readAsStringSync());

      expect(resolverJson, {
        "__refs": {
          "users": 1,
          "users.encrypted": 1,
        },
        "__values": {
          "users": "users",
          "users.encrypted": "users.encrypted",
        }
      });
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
          'users:1': {'name': 'User 1'},
          'users:2': {'name': 'User 2'}
        },
      );
    });

    test('Encrypts data when explicitly enabled for a collection', () async {
      Loon.configure(
        persistor: TestFilePersistor(
          settings: const FilePersistorSettings(encrypted: false),
        ),
      );

      final userCollection = Loon.collection(
        'users',
        fromJson: TestUserModel.fromJson,
        toJson: (user) => user.toJson(),
        persistorSettings: const FilePersistorSettings(encrypted: true),
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
          'users:1': {'name': 'User 1'},
          'users:2': {'name': 'User 2'}
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

    final userCollection = Loon.collection(
      'users',
      fromJson: TestUserModel.fromJson,
      toJson: (user) => user.toJson(),
      persistorSettings: const FilePersistorSettings(encrypted: false),
    );

    final user1 = TestUserModel('User 1');
    final userDoc1 = userCollection.doc('1');
    final user2 = TestUserModel('User 2');
    final userDoc2 = userCollection.doc('2');

    userDoc1.create(user1);
    userDoc2.create(user2);

    await completer.onPersist;

    final file = File('${testDirectory.path}/loon/users.json');
    final json = jsonDecode(file.readAsStringSync());

    expect(
      json,
      {
        'users:1': {'name': 'User 1'},
        'users:2': {'name': 'User 2'}
      },
    );
  });

// This scenario takes a bit of a description. In the situation where a file for a collection is unencrypted,
// but encryption settings now specify that the collection should be encrypted, then the unencrypted file should be hydrated into memory,
// but any subsequent persistence calls for that collection should move the updated data from the unencrypted data store to the encrypted data store.
// Once all the data has been moved, the unencrypted file should be deleted.
  test('Encrypts collections hydrated from unencrypted files', () async {
    Loon.configure(
      persistor: TestFilePersistor(
        settings: const FilePersistorSettings(encrypted: true),
      ),
    );

    Directory('${testDirectory.path}/loon').createSync();
    final plaintextFile = File('${testDirectory.path}/loon/users.json');
    plaintextFile.writeAsStringSync(
      jsonEncode({
        'users:1': {'name': 'User 1'},
        'users:2': {'name': 'User 2'}
      }),
    );

    await Loon.hydrate();

    final userCollection = Loon.collection(
      'users',
      fromJson: TestUserModel.fromJson,
      toJson: (user) => user.toJson(),
    );

    final user3 = TestUserModel('User 3');
    userCollection.doc('3').create(user3);

    await completer.onPersist;

    final encryptedFile =
        File('${testDirectory.path}/loon/users.encrypted.json');
    final json = decryptData(encryptedFile.readAsStringSync());

    // The new user should have been written to an encrypted file, since the persistor was configured with encryption
    // enabled globally.
    expect(
      json,
      {
        'users:3': {'name': 'User 3'}
      },
    );

    final user1 = TestUserModel('User 1 updated');
    final user2 = TestUserModel('User 2 updated');

    userCollection.doc('1').update(user1);
    userCollection.doc('2').update(user2);

    await completer.onPersist;

    // The changes to the documents hydrated from the unencrypted data store should be persisted into the encrypted data store
    // and now that the unencrypted store is empty, it should have been deleted.

    final updatedJson = decryptData(encryptedFile.readAsStringSync());

    expect(
      updatedJson,
      {
        'users:1': {'name': 'User 1 updated'},
        'users:2': {'name': 'User 2 updated'},
        'users:3': {'name': 'User 3'}
      },
    );

    expect(plaintextFile.existsSync(), false);
  });
}
