import 'package:flutter_test/flutter_test.dart';
import 'package:loon/loon.dart';

import '../models/test_indexed_db_persistor.dart';
import '../models/test_user_model.dart';
import '../utils.dart';

void main() {
  TestWidgetsFlutterBinding.ensureInitialized();

  late PersistorCompleter completer;
  late TestIndexedDBPersistor persistor;

  setUp(() {
    persistor = TestIndexedDBPersistor();
    completer = TestIndexedDBPersistor.completer = PersistorCompleter();

    Loon.configure(persistor: persistor);
  });

  tearDown(() async {
    await Loon.clearAll();
  });

  group('IndexedDBPersistor', () {
    group(
      'Persist',
      () {
        test('Persists documents', () async {
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
            await persistor.getStore('__store__'),
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
        });
      },
    );

    group('hydrate', () {
      test('Hydrates documents', () async {
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

        expect(await persistor.getStore('__store__'), {
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

        expect(await persistor.getStore('my_friends'), {
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

        expect(await persistor.getStore('__resolver__'), {
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

        // Set the persistor to null before clearing the store so that the persisted data is not deleted.
        Loon.configure(persistor: null);
        await Loon.clearAll();

        expect(userCollection.get().isEmpty, true);
        expect(friendsCollection.get().isEmpty, true);
        expect(userFriendsCollection.get().isEmpty, true);
        expect(currentUserDoc.get(), null);

        // Then reinitialize a new persistor so that it reads the persisted data on hydration.
        Loon.configure(persistor: TestIndexedDBPersistor());

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
    });
  });
}
