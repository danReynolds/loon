import 'package:flutter_test/flutter_test.dart';
import 'package:loon/loon.dart';
import '../../models/test_indexed_db_persistor.dart';
import '../../models/test_user_model.dart';
import '../../utils.dart';

void main() {
  TestWidgetsFlutterBinding.ensureInitialized();

  late PersistorCompleter completer;
  late TestIndexedDBPersistor persistor;

  setUp(() {
    completer = TestIndexedDBPersistor.completer = PersistorCompleter();
    persistor = TestIndexedDBPersistor(
      settings: const PersistorSettings(encrypted: true),
    );
  });

  tearDown(() async {
    await Loon.clearAll();
  });

  group('Encrypted IndexedDBPersistor', () {
    test(
      'Persists encrypted data',
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

        expect(await persistor.getStore('__store__'), {
          "": {
            "users": {
              "__values": {
                '1': {'name': 'User 1'},
              },
            },
          }
        });

        expect(await persistor.getStore('__store__', encrypted: true), {
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

        expect(userCollection.exists(), false);
        expect(encryptedUsersCollection.exists(), false);

        // Reinitialize the persistor ahead of hydration.
        Loon.configure(
          persistor: TestIndexedDBPersistor(
            settings: const PersistorSettings(encrypted: true),
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
      },
    );
  });
}
