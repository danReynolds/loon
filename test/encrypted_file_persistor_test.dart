import 'dart:convert';
import 'dart:io';
import 'package:encrypt/encrypt.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:loon/loon.dart';
import 'loon_test.dart';
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

class TestEncryptionFilePersistor extends FilePersistor {
  TestEncryptionFilePersistor({
    required super.persistenceThrottle,
    required super.persistorSettings,
    required super.onPersist,
  });

  @override

  /// Override the initialization of the encrypter to use a test key instead of accessing FlutterSecureStorage
  /// which is not available in the test environment.
  Future<Encrypter?> initEncrypter() async {
    return Encrypter(AES(testEncryptionKey, mode: AESMode.cbc));
  }
}

void main() {
  ResetCompleter persistCompleter = ResetCompleter();

  setUp(() {
    persistCompleter = ResetCompleter();
    testDirectory = Directory.systemTemp.createTempSync('test_dir');
    final mockPathProvider = MockPathProvider();
    PathProviderPlatform.instance = mockPathProvider;
  });

  tearDown(() async {
    testDirectory.deleteSync(recursive: true);
    await Loon.clear();
  });

  group('hydrate', () {
    setUp(() {
      Loon.configure(
        persistor: TestEncryptionFilePersistor(
          persistenceThrottle: const Duration(milliseconds: 1),
          persistorSettings: EncryptedFilePersistorSettings(),
          onPersist: (_) {
            persistCompleter.complete();
          },
        ),
      );
    });

    test('Hydrates data from encrypted persistence files into collections',
        () async {
      final userCollection = Loon.collection(
        'users',
        fromJson: TestUserModel.fromJson,
        toJson: (user) => user.toJson(),
      );

      final file = File('${testDirectory.path}/loon/users.encrypted.json');
      Directory('${testDirectory.path}/loon').createSync();
      file.writeAsStringSync(
        encryptData({
          'users:1': {'name': 'User 1'},
          'users:2': {'name': 'User 2'}
        }),
      );

      await Loon.hydrate();

      expect(
        userCollection.get(),
        [
          DocumentSnapshotMatcher(
            DocumentSnapshot(
              doc: userCollection.doc('1'),
              data: TestUserModel('User 1'),
            ),
          ),
          DocumentSnapshotMatcher(
            DocumentSnapshot(
              doc: userCollection.doc('2'),
              data: TestUserModel('User 2'),
            ),
          ),
        ],
      );
    });

    test(
        'Merges hydrated data from encrypted and non-encrypted persistence files into collection',
        () async {
      final userCollection = Loon.collection(
        'users',
        fromJson: TestUserModel.fromJson,
        toJson: (user) => user.toJson(),
      );

      Directory('${testDirectory.path}/loon').createSync();
      final encryptedFile =
          File('${testDirectory.path}/loon/users.encrypted.json');
      final plaintextFile = File('${testDirectory.path}/loon/users.json');
      plaintextFile.writeAsStringSync(
        jsonEncode({
          'users:1': {'name': 'User 1'},
          'users:3': {'name': 'User 3'}
        }),
      );
      encryptedFile.writeAsStringSync(
        encryptData({
          'users:1': {'name': 'User 1'},
          'users:2': {'name': 'User 2'}
        }),
      );

      await Loon.hydrate();

      expect(
        userCollection.get(),
        unorderedEquals([
          DocumentSnapshotMatcher(
            DocumentSnapshot(
              doc: userCollection.doc('1'),
              data: TestUserModel('User 1'),
            ),
          ),
          DocumentSnapshotMatcher(
            DocumentSnapshot(
              doc: userCollection.doc('3'),
              data: TestUserModel('User 3'),
            ),
          ),
          DocumentSnapshotMatcher(
            DocumentSnapshot(
              doc: userCollection.doc('2'),
              data: TestUserModel('User 2'),
            ),
          ),
        ]),
      );
    });
  });

  group('persist', () {
    test('Encrypts data when enabled globally for all collections', () async {
      Loon.configure(
        persistor: TestEncryptionFilePersistor(
          persistenceThrottle: const Duration(milliseconds: 1),
          persistorSettings: EncryptedFilePersistorSettings(),
          onPersist: (_) {
            persistCompleter.complete();
          },
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

      await persistCompleter.future;

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
        persistor: TestEncryptionFilePersistor(
          persistenceThrottle: const Duration(milliseconds: 1),
          persistorSettings:
              EncryptedFilePersistorSettings(encryptionEnabled: false),
          onPersist: (_) {
            persistCompleter.complete();
          },
        ),
      );

      final userCollection = Loon.collection(
        'users',
        fromJson: TestUserModel.fromJson,
        toJson: (user) => user.toJson(),
        persistorSettings: EncryptedFilePersistorSettings(
          encryptionEnabled: true,
        ),
      );

      final user1 = TestUserModel('User 1');
      final userDoc1 = userCollection.doc('1');
      final user2 = TestUserModel('User 2');
      final userDoc2 = userCollection.doc('2');

      userDoc1.create(user1);
      userDoc2.create(user2);

      await persistCompleter.future;

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
      persistor: TestEncryptionFilePersistor(
        persistenceThrottle: const Duration(milliseconds: 1),
        persistorSettings: EncryptedFilePersistorSettings(),
        onPersist: (_) {
          persistCompleter.complete();
        },
      ),
    );

    final userCollection = Loon.collection(
      'users',
      fromJson: TestUserModel.fromJson,
      toJson: (user) => user.toJson(),
      persistorSettings: EncryptedFilePersistorSettings(
        encryptionEnabled: false,
      ),
    );

    final user1 = TestUserModel('User 1');
    final userDoc1 = userCollection.doc('1');
    final user2 = TestUserModel('User 2');
    final userDoc2 = userCollection.doc('2');

    userDoc1.create(user1);
    userDoc2.create(user2);

    await persistCompleter.future;

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
      persistor: TestEncryptionFilePersistor(
        persistenceThrottle: const Duration(milliseconds: 1),
        persistorSettings: EncryptedFilePersistorSettings(),
        onPersist: (_) {
          persistCompleter.complete();
        },
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

    await persistCompleter.future;

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

    await persistCompleter.future;

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
