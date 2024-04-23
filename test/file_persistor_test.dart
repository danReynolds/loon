import 'dart:convert';
import 'dart:io';
import 'package:flutter_test/flutter_test.dart';
import 'package:loon/loon.dart';

// ignore: depend_on_referenced_packages
import 'package:path_provider_platform_interface/path_provider_platform_interface.dart';
// ignore: depend_on_referenced_packages
import 'package:plugin_platform_interface/plugin_platform_interface.dart';

import 'matchers/document_snapshot.dart';
import 'models/test_large_model.dart';
import 'models/test_user_model.dart';
import 'utils.dart';

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
  PersistorCompleter completer = PersistorCompleter();

  setUp(() {
    completer = PersistorCompleter();
    testDirectory = Directory.systemTemp.createTempSync('test_dir');
    final mockPathProvider = MockPathProvider();
    PathProviderPlatform.instance = mockPathProvider;

    Loon.configure(
      persistor: FilePersistor(
        persistenceThrottle: const Duration(milliseconds: 1),
        onPersist: (_) {
          completer.persistComplete();
        },
        onClear: (_) {
          completer.clearComplete();
        },
        onClearAll: () {
          completer.clearAllComplete();
        },
      ),
    );
  });

  tearDown(() async {
    testDirectory.deleteSync(recursive: true);
    await Loon.clearAll();
  });

  group('persist', () {
    test(
      'Persists new documents',
      () async {
        final userCollection = Loon.collection(
          'users',
          fromJson: TestUserModel.fromJson,
          toJson: (user) => user.toJson(),
        );

        userCollection.doc('1').create(TestUserModel('User 1'));
        userCollection.doc('2').create(TestUserModel('User 2'));

        await completer.onPersistComplete;

        final file = File('${testDirectory.path}/loon/users.json');
        final json = jsonDecode(file.readAsStringSync());

        expect(
          json,
          {
            'users:1': {'name': 'User 1'},
            'users:2': {'name': 'User 2'}
          },
        );
      },
    );

    test(
      'Persists updated documents',
      () async {
        final userCollection = Loon.collection(
          'users',
          fromJson: TestUserModel.fromJson,
          toJson: (user) => user.toJson(),
        );

        userCollection.doc('1').create(TestUserModel('User 1'));
        userCollection.doc('2').create(TestUserModel('User 2'));

        await completer.onPersistComplete;

        userCollection.doc('2').update(TestUserModel('User 2 updated'));

        await completer.onPersistComplete;

        final file = File('${testDirectory.path}/loon/users.json');
        final json = jsonDecode(file.readAsStringSync());

        expect(
          json,
          {
            'users:1': {'name': 'User 1'},
            'users:2': {'name': 'User 2 updated'}
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

        await completer.onPersistComplete;

        userCollection.doc('2').delete();

        await completer.onPersistComplete;

        final file = File('${testDirectory.path}/loon/users.json');
        final json = jsonDecode(file.readAsStringSync());

        expect(
          json,
          {
            'users:1': {'name': 'User 1'}
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

        await completer.onPersistComplete;

        expect(
          file.existsSync(),
          true,
        );

        // If all documents of a file are deleted, the file itself should be deleted.
        userCollection.doc('1').delete();
        userCollection.doc('2').delete();

        await completer.onPersistComplete;

        expect(
          file.existsSync(),
          false,
        );
      },
    );

    test(
      'Persists documents by their persistence key',
      () async {
        final userCollection = Loon.collection(
          'users',
          fromJson: TestUserModel.fromJson,
          toJson: (user) => user.toJson(),
          persistorSettings: FilePersistorSettings(
            getPersistenceKey: (doc) {
              if (doc.id == '1') {
                return 'users';
              }
              return 'other_users';
            },
          ),
        );

        userCollection.doc('1').create(TestUserModel('User 1'));
        userCollection.doc('2').create(TestUserModel('User 2'));

        await completer.onPersistComplete;

        final usersFile = File('${testDirectory.path}/loon/users.json');
        final otherUsersFile =
            File('${testDirectory.path}/loon/other_users.json');
        final usersJson = jsonDecode(usersFile.readAsStringSync());
        final otherUsersJson = jsonDecode(otherUsersFile.readAsStringSync());

        expect(
          usersJson,
          {
            'users:1': {'name': 'User 1'}
          },
        );

        expect(
          otherUsersJson,
          {
            'users:2': {'name': 'User 2'}
          },
        );
      },
    );

    test(
      'Moves documents that change persistence files',
      () async {
        final userCollection = Loon.collection(
          'users',
          fromJson: TestUserModel.fromJson,
          toJson: (user) => user.toJson(),
          persistorSettings: FilePersistorSettings(
            getPersistenceKey: (doc) {
              if (doc.get()?.data.name.endsWith('updated')) {
                return 'updated_users';
              }
              return 'users';
            },
          ),
        );

        userCollection.doc('1').create(TestUserModel('User 1'));
        userCollection.doc('2').create(TestUserModel('User 2'));

        await completer.onPersistComplete;

        userCollection.doc('2').update(TestUserModel('User 2 updated'));

        await completer.onPersistComplete;

        final usersFile = File('${testDirectory.path}/loon/users.json');
        final updatedUsersFile =
            File('${testDirectory.path}/loon/updated_users.json');
        final usersJson = jsonDecode(usersFile.readAsStringSync());
        final updatedUsersJson =
            jsonDecode(updatedUsersFile.readAsStringSync());

        expect(
          usersJson,
          {
            'users:1': {'name': 'User 1'}
          },
        );

        expect(
          updatedUsersJson,
          {
            'users:2': {'name': 'User 2 updated'}
          },
        );
      },
    );
  });

  group('hydrate', () {
    test('Hydrates data from persistence files into collections', () async {
      final userCollection = Loon.collection(
        'users',
        fromJson: TestUserModel.fromJson,
        toJson: (user) => user.toJson(),
      );

      final file = File('${testDirectory.path}/loon/users.json');
      Directory('${testDirectory.path}/loon').createSync();
      file.writeAsStringSync(
        jsonEncode(
          {
            'users:1': {'name': 'User 1'},
            'users:2': {'name': 'User 2'}
          },
        ),
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

    test('Merges existing collections', () async {
      final userCollection = Loon.collection(
        'users',
        fromJson: TestUserModel.fromJson,
        toJson: (user) => user.toJson(),
      );

      userCollection.doc('1').create(TestUserModel('User 1'));

      await completer.onPersistComplete;

      final file = File('${testDirectory.path}/loon/users.json');
      file.writeAsStringSync(
        jsonEncode(
          {
            'users:2': {'name': 'User 2'}
          },
        ),
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

    test('Hydrates large persistence files', () async {
      int size = 20000;

      List<TestLargeModel> models =
          List.generate(size, (_) => generateRandomModel());

      final collectionJson = models.fold({}, (acc, model) {
        acc['users:${model.id}'] = model.toJson();
        return acc;
      });
      final file = File('${testDirectory.path}/loon/users.json');
      file.writeAsStringSync(jsonEncode(collectionJson));

      await Loon.hydrate();

      final largeModelCollection = Loon.collection(
        'users',
        fromJson: TestLargeModel.fromJson,
        toJson: (user) => user.toJson(),
      );

      final collectionSize = await measureDuration(
        'Initial collection query',
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

          await completer.onPersistComplete;

          expect(file.existsSync(), true);

          userCollection.delete();

          await completer.onClearComplete;

          expect(file.existsSync(), false);
        },
      );

      // In this scenario, the user collection is spread across multiple data stores. Since each of those
      // data stores are empty after the collection is cleared, they should all be deleted.
      test(
        "Deletes all of the collection's data stores",
        () async {
          final userCollection = Loon.collection(
            'users',
            fromJson: TestUserModel.fromJson,
            toJson: (user) => user.toJson(),
            persistorSettings: FilePersistorSettings(
              getPersistenceKey: (snap) {
                return 'users${snap.id}';
              },
            ),
          );

          userCollection.doc('1').create(TestUserModel('User 1'));
          userCollection.doc('2').create(TestUserModel('User 2'));
          userCollection.doc('3').create(TestUserModel('User 3'));

          final file1 = File('${testDirectory.path}/loon/users1.json');
          final file2 = File('${testDirectory.path}/loon/users2.json');
          final file3 = File('${testDirectory.path}/loon/users3.json');

          await completer.onPersistComplete;

          expect(file1.existsSync(), true);
          expect(file2.existsSync(), true);
          expect(file3.existsSync(), true);

          userCollection.delete();

          await completer.onClearComplete;

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
              );

          userCollection.doc('1').create(TestUserModel('User 1'));
          userCollection.doc('2').create(TestUserModel('User 2'));
          friendsCollection.doc('1').create(TestUserModel('Friend 1'));

          final userFile = File('${testDirectory.path}/loon/users.json');
          final friendsFile =
              File('${testDirectory.path}/loon/users__1__friends.json');

          await completer.onPersistComplete;

          expect(userFile.existsSync(), true);
          expect(friendsFile.existsSync(), true);

          userCollection.delete();

          await completer.onClearComplete;

          expect(userFile.existsSync(), false);
          expect(friendsFile.existsSync(), false);
        },
      );

      // In this scenario, multiple collections share data stores and the data store should not be deleted
      // since it still has documents from another collection.
      test(
        'Retains data stores that share collections',
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
            persistorSettings: FilePersistorSettings(
              getPersistenceKey: (snap) {
                return 'users';
              },
            ),
          );

          userCollection.doc('1').create(TestUserModel('User 1'));
          userCollection.doc('2').create(TestUserModel('User 2'));
          friendsCollection.doc('1').create(TestUserModel('Friend 1'));
          friendsCollection.doc('2').create(TestUserModel('Friend 2'));

          final file = File('${testDirectory.path}/loon/users.json');

          await completer.onPersistComplete;

          Json json = jsonDecode(file.readAsStringSync());
          expect(
            json,
            {
              'users:1': {'name': 'User 1'},
              'users:2': {'name': 'User 2'},
              'friends:1': {'name': 'Friend 1'},
              'friends:2': {'name': 'Friend 2'}
            },
          );

          userCollection.delete();

          await completer.onClearComplete;

          json = jsonDecode(file.readAsStringSync());
          expect(
            json,
            {
              'friends:1': {'name': 'Friend 1'},
              'friends:2': {'name': 'Friend 2'}
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

          await completer.onPersistComplete;

          expect(file.existsSync(), true);

          await Loon.clearAll();

          expect(file.existsSync(), false);
        },
      );
    },
  );
}
