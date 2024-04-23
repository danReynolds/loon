import 'package:flutter_test/flutter_test.dart';
import 'package:loon/loon.dart';

import 'models/test_persistor.dart';
import 'models/test_user_model.dart';
import 'utils.dart';

Future<void> asyncEvent() {
  return Future.delayed(const Duration(milliseconds: 1), () => null);
}

void main() {
  group('Create document', () {
    tearDown(() {
      Loon.clearAll();
    });

    test(
      'User document created successfully',
      () {
        final user = TestUserModel('User 1');
        final userDoc = TestUserModel.store.doc('1');

        userDoc.create(user);

        expect(
          Loon.inspect()['store'],
          {
            "users": {
              "__values": {
                "1": DocumentSnapshot(
                  doc: userDoc,
                  data: user,
                ),
              }
            }
          },
        );
      },
    );

    test('JSON user document created successfully', () {
      final userCollection = Loon.collection('users');
      final userDoc = userCollection.doc('2');
      final userJson = {
        "name": "User 2",
      };

      userDoc.create(userJson);

      expect(
        Loon.inspect()['store'],
        {
          "users": {
            "__values": {
              "2": DocumentSnapshot(
                doc: userDoc,
                data: userJson,
              ),
            },
          }
        },
      );
    });

    test('Persisted instance document added without serializer throws error',
        () {
      expect(
        () => Loon.collection(
          'users',
          persistorSettings: const PersistorSettings(),
        ).doc('1').create(TestUserModel('1')),
        throwsException,
      );
    });

    test('Duplicate user document created fails', () {
      final user = TestUserModel('User 1');
      final userDoc = TestUserModel.store.doc('1');

      userDoc.create(user);

      expect(
        () => userDoc.create(user),
        throwsException,
      );
    });
  });

  group('Read document', () {
    tearDown(() {
      Loon.clearAll();
    });

    test('Instance user document read successfully', () {
      final user = TestUserModel('User 1');
      final userDoc = TestUserModel.store.doc('1');

      userDoc.create(user);

      expect(
        userDoc.get(),
        DocumentSnapshot(
          doc: userDoc,
          data: user,
        ),
      );
    });

    test('JSON user document read successfully', () {
      final userCollection = Loon.collection('users');
      final userDoc = userCollection.doc('2');
      final userJson = {
        "name": "User 2",
      };

      userDoc.create(userJson);

      expect(
        userDoc.get(),
        DocumentSnapshot(
          doc: userDoc,
          data: userJson,
        ),
      );
    });
  });

  group('Update document', () {
    tearDown(() {
      Loon.clearAll();
    });

    test('Deserialized document updated successfully', () {
      final updatedUser = TestUserModel('User 1 updated');
      final userDoc = TestUserModel.store.doc('1');

      userDoc.create(TestUserModel('User 1'));
      userDoc.update(updatedUser);

      expect(
        userDoc.get(),
        DocumentSnapshot(
          doc: userDoc,
          data: updatedUser,
        ),
      );
    });

    test('JSON document updated successfully', () {
      final userCollection = Loon.collection('users');
      final userDoc = userCollection.doc('2');
      final userJson = {
        "name": "User 2",
      };
      final updatedUserJson = {
        "name": "User 2 updated",
      };

      userDoc.create(userJson);
      userDoc.update(updatedUserJson);

      expect(
        userDoc.get(),
        DocumentSnapshot(
          doc: userDoc,
          data: updatedUserJson,
        ),
      );
    });

    test('Updating a non-existent document throws an error', () {
      final updatedUser = TestUserModel('User 1');
      final userDoc = TestUserModel.store.doc('1');

      expect(
        () => userDoc.update(updatedUser),
        throwsException,
      );
    });

    test('Persisted instance document updated without serializer throws error',
        () {
      expect(
        () => Loon.collection(
          'users',
          persistorSettings: const PersistorSettings(),
        ).doc('1').update(TestUserModel('1')),
        throwsException,
      );
    });
  });

  group('Modify document', () {
    tearDown(() {
      Loon.clearAll();
    });

    test('Deserialized document modified successfully', () {
      final updatedUser = TestUserModel('User 1 updated');
      final userDoc = TestUserModel.store.doc('1');

      userDoc.create(TestUserModel('User 1'));
      userDoc.modify((userSnap) => updatedUser);

      expect(
        userDoc.get(),
        DocumentSnapshot(
          doc: userDoc,
          data: updatedUser,
        ),
      );
    });

    test(
      'Modifying a new document creates the document',
      () {
        final newUser = TestUserModel('User 1');
        final userDoc = TestUserModel.store.doc('1');

        expect(
          userDoc.modify((_) => newUser),
          DocumentSnapshot(
            doc: userDoc,
            data: newUser,
          ),
        );
      },
    );

    test('JSON document modified successfully', () {
      final userCollection = Loon.collection('users');
      final userDoc = userCollection.doc('2');
      final userJson = {
        "name": "User 2",
      };
      final updatedUserJson = {
        "name": "User 2 updated",
      };

      userDoc.create(userJson);
      userDoc.modify((userSnap) => updatedUserJson);

      expect(
        userDoc.get(),
        DocumentSnapshot(
          doc: userDoc,
          data: updatedUserJson,
        ),
      );
    });

    test('Persisted instance document modified without serializer throws error',
        () {
      expect(
        () => Loon.collection(
          'users',
          persistorSettings: const PersistorSettings(),
        ).doc('1').modify((userSnap) => TestUserModel('1')),
        throwsException,
      );
    });
  });

  group('Delete document', () {
    tearDown(() {
      Loon.clearAll();
    });

    test('Document deleted successfully', () {
      final user = TestUserModel('User 1');
      final userDoc = TestUserModel.store.doc('1');

      userDoc.create(user);
      userDoc.delete();

      expect(userDoc.exists(), false);

      expect(
        Loon.inspect()["store"],
        {},
      );
    });
  });

  group('Stream document', () {
    tearDown(() {
      return Loon.clearAll();
    });

    test('Emits the current document', () async {
      final user = TestUserModel('User 1');
      final userDoc = TestUserModel.store.doc('1');

      userDoc.create(user);

      final userStream = userDoc.stream();

      expectLater(
        userStream,
        emits(
          DocumentSnapshot(
            doc: userDoc,
            data: user,
          ),
        ),
      );
    });

    test('Emits updates to the document', () async {
      final user = TestUserModel('User 1');
      final updatedUser = TestUserModel('Updated User 1');
      final userDoc = TestUserModel.store.doc('1');

      final userObs = userDoc.observe();

      userDoc.create(user);

      await asyncEvent();
      userDoc.update(updatedUser);

      await asyncEvent();
      userDoc.delete();

      await asyncEvent();

      userObs.dispose();

      expectLater(
        userObs.stream(),
        emitsInOrder([
          null,
          DocumentSnapshot(
            doc: userDoc,
            data: user,
          ),
          DocumentSnapshot(
            doc: userDoc,
            data: updatedUser,
          ),
          null,
          emitsDone,
        ]),
      );
    });
  });

  group('Stream document changes', () {
    tearDown(() {
      Loon.clearAll();
    });

    test('Returns a stream of changes to the document', () async {
      final userDoc = TestUserModel.store.doc('1');
      final user = TestUserModel('User 1');
      final userUpdated = TestUserModel('User 1 updated');

      final queryFuture = userDoc.streamChanges().take(2).toList();

      userDoc.create(user);

      await asyncEvent();

      userDoc.update(userUpdated);

      final snaps = await queryFuture;

      // Add document
      expect(
        snaps[0].event,
        EventTypes.added,
      );
      expect(
        snaps[0].prevData,
        null,
      );
      expect(
        snaps[0].data,
        user,
      );

      // Update document
      expect(
        snaps[1].event,
        EventTypes.modified,
      );
      expect(
        snaps[1].prevData,
        user,
      );
      expect(
        snaps[1].data,
        userUpdated,
      );
    });
  });

  group('Query documents', () {
    tearDown(() {
      Loon.clearAll();
    });

    test('Returns documents that satisfy the query', () {
      final user = TestUserModel('User 1');
      final user2 = TestUserModel('User 2');
      final userDoc = TestUserModel.store.doc('1');
      final userDoc2 = TestUserModel.store.doc('2');

      userDoc.create(user);
      userDoc2.create(user2);

      final querySnap =
          TestUserModel.store.where((snap) => snap.id == '1').get();

      expect(querySnap.length, 1);
      expect(
        querySnap.first,
        DocumentSnapshot(
          doc: userDoc,
          data: user,
        ),
      );
    });
  });

  group('Stream queries', () {
    tearDown(() {
      Loon.clearAll();
    });

    test(
      'Returns a stream of documents that satisfy the query',
      () async {
        final user = TestUserModel('User 1');
        final user2 = TestUserModel('User 2');
        final userDoc = TestUserModel.store.doc('1');
        final userDoc2 = TestUserModel.store.doc('2');

        userDoc.create(user);
        userDoc2.create(user2);

        final queryStream =
            TestUserModel.store.where((snap) => snap.id == '1').stream();

        final querySnaps = await queryStream.take(1).toList();

        expect(
          querySnaps,
          [
            [
              DocumentSnapshot(
                doc: userDoc,
                data: user,
              ),
            ]
          ],
        );
      },
    );

    test('Updates the stream of documents when they change', () async {
      final user = TestUserModel('User 1');
      final user2 = TestUserModel('User 2');
      final userDoc = TestUserModel.store.doc('1');

      userDoc.create(user);

      await asyncEvent();

      final queryStream = TestUserModel.store
          .where((snap) {
            return snap.data.name == 'User 1';
          })
          .stream()
          .take(2);

      await asyncEvent();

      userDoc.update(user2);

      final querySnaps = await queryStream.toList();
      expect(
        querySnaps,
        [
          [
            DocumentSnapshot(
              doc: userDoc,
              data: user,
            ),
          ],
          [],
        ],
      );
    });

    test(
        'Correctly handles the scenario where a collection is removed and written to in the same task',
        () async {
      final user = TestUserModel('User 1');
      final user2 = TestUserModel('User 2');
      final userDoc = TestUserModel.store.doc('1');
      final userDoc2 = TestUserModel.store.doc('2');

      userDoc.create(user);
      userDoc2.create(user2);

      await asyncEvent();

      final queryStream = TestUserModel.store.stream().take(2);

      await asyncEvent();

      TestUserModel.store.delete();
      userDoc.create(user);

      final querySnaps = await queryStream.toList();

      expect(
        querySnaps,
        [
          [
            DocumentSnapshot(
              doc: userDoc,
              data: user,
            ),
            DocumentSnapshot(
              doc: userDoc2,
              data: user2,
            ),
          ],
          [
            DocumentSnapshot(
              doc: userDoc,
              data: user,
            ),
          ],
        ],
      );
    });
  });

  group('Stream query changes', () {
    tearDown(() {
      Loon.clearAll();
    });

    test('Returns a stream of changes to documents', () async {
      final user = TestUserModel('User 1');
      final user2 = TestUserModel('User 2');
      final userDoc = TestUserModel.store.doc('1');
      final userDoc2 = TestUserModel.store.doc('2');
      final updatedUser = TestUserModel('User 1 updated');

      final changeSnaps = TestUserModel.store.streamChanges().take(2).toList();

      userDoc.create(user);
      userDoc2.create(user2);

      await asyncEvent();

      userDoc.update(updatedUser);

      expect(
        await changeSnaps,
        [
          [
            DocumentChangeSnapshot(
              doc: userDoc,
              data: user,
              event: EventTypes.added,
              prevData: null,
            ),
            DocumentChangeSnapshot(
              doc: userDoc2,
              data: user2,
              event: EventTypes.added,
              prevData: null,
            ),
          ],
          [
            DocumentChangeSnapshot(
              doc: userDoc,
              data: updatedUser,
              event: EventTypes.modified,
              prevData: user,
            ),
          ]
        ],
      );
    });

    test('Localizes broadcast event change types to the query', () async {
      final user = TestUserModel('User 1');
      final userDoc = TestUserModel.store.doc('1');

      final changeSnaps = TestUserModel.store
          .where((snap) => snap.data.name == 'User 1 updated')
          .streamChanges()
          .take(1)
          .toList();

      userDoc.create(user);
      await asyncEvent();
      final updatedUser = TestUserModel('User 1 updated');
      userDoc.update(updatedUser);

      expect(
        await changeSnaps,
        [
          [
            DocumentChangeSnapshot(
              doc: userDoc,
              data: updatedUser,
              // The global event is a [BroadcastEventTypes.modified] when the user is updated,
              // but to this query, it should be a [BroadcastEventTypes.added] event since previously
              // it was not included and now it is.
              event: EventTypes.added,
              prevData: null,
            ),
          ],
        ],
      );
    });

    test(
        'Correctly handles the scenario where a collection is removed and written to in the same task',
        () async {
      final user = TestUserModel('User 1');
      final user2 = TestUserModel('User 2');
      final userDoc = TestUserModel.store.doc('1');
      final userDoc2 = TestUserModel.store.doc('2');

      final changeSnaps = TestUserModel.store.streamChanges().take(2).toList();

      userDoc.create(user);
      userDoc2.create(user2);

      await asyncEvent();

      TestUserModel.store.delete();
      userDoc.create(user);

      expect(
        await changeSnaps,
        [
          [
            DocumentChangeSnapshot(
              doc: userDoc,
              data: user,
              prevData: null,
              event: EventTypes.added,
            ),
            DocumentChangeSnapshot(
              doc: userDoc2,
              data: user2,
              prevData: null,
              event: EventTypes.added,
            )
          ],
          [
            DocumentChangeSnapshot(
              doc: userDoc,
              data: null,
              prevData: user,
              event: EventTypes.removed,
            ),
            DocumentChangeSnapshot(
              doc: userDoc2,
              data: null,
              prevData: user2,
              event: EventTypes.removed,
            ),
            DocumentChangeSnapshot(
              doc: userDoc,
              data: user,
              prevData: null,
              event: EventTypes.added,
            ),
          ],
        ],
      );
    });
  });

  group(
    'Delete collection',
    () {
      tearDown(() {
        Loon.clearAll();
      });

      test('Deletes the collection', () {
        final userDoc = TestUserModel.store.doc('1');
        final userDoc2 = TestUserModel.store.doc('2');

        final userData = TestUserModel('User 1');
        final userData2 = TestUserModel('User 2');

        userDoc.create(userData);
        userDoc2.create(userData2);

        expect(
          Loon.inspect()['store'],
          {
            "users": {
              "__values": {
                "1": DocumentSnapshot(
                  doc: userDoc,
                  data: userData,
                ),
                "2": DocumentSnapshot(
                  doc: userDoc2,
                  data: userData2,
                ),
              }
            }
          },
        );

        TestUserModel.store.delete();

        expect(
          Loon.inspect()['store'],
          {},
        );
      });

      test('Deletes subcollections of the collection', () {
        final userDoc = TestUserModel.store.doc('1');
        final userDoc2 = TestUserModel.store.doc('2');

        final userData = TestUserModel('User 1');
        final userData2 = TestUserModel('User 2');

        final friendDoc = userDoc
            .subcollection<TestUserModel>(
              'friends',
              fromJson: TestUserModel.fromJson,
              toJson: (snap) => snap.toJson(),
            )
            .doc('2');

        userDoc.create(userData);
        friendDoc.create(userData2);
        userDoc2.create(userData2);

        expect(
          Loon.inspect()['store'],
          {
            "users": {
              "__values": {
                "1": DocumentSnapshot(
                  doc: userDoc,
                  data: userData,
                ),
                "2": DocumentSnapshot(
                  doc: userDoc2,
                  data: userData2,
                ),
              },
              "1": {
                "friends": {
                  "__values": {
                    "2": DocumentSnapshot(
                      doc: friendDoc,
                      data: userData2,
                    ),
                  }
                }
              }
            },
          },
        );

        TestUserModel.store.delete();

        expect(
          Loon.inspect()['store'],
          {},
        );
      });

      test(
        'Broadcasts the delete to observers of the collection and subcollections',
        () async {
          final userDoc = TestUserModel.store.doc('1');
          final userDoc2 = TestUserModel.store.doc('2');

          final userData = TestUserModel('User 1');
          final userData2 = TestUserModel('User 2');

          final friendDoc = userDoc
              .subcollection<TestUserModel>(
                'friends',
                fromJson: TestUserModel.fromJson,
                toJson: (snap) => snap.toJson(),
              )
              .doc('2');

          userDoc.create(userData);
          friendDoc.create(userData2);
          userDoc2.create(userData2);

          final userDocStream = userDoc.stream();
          final userCollectionStream = TestUserModel.store.stream();
          final friendDocStream = friendDoc.stream();
          final friendCollectionStream =
              userDoc.subcollection<TestUserModel>('friends').stream();

          TestUserModel.store.delete();

          final userDocData = await userDocStream.take(2).toList();
          final userCollectionData =
              await userCollectionStream.take(2).toList();
          final friendDocData = await friendDocStream.take(2).toList();
          final friendCollectionData =
              await friendCollectionStream.take(2).toList();

          expect(
            userDocData,
            [
              DocumentSnapshot(
                doc: userDoc,
                data: userData,
              ),
              null,
            ],
          );

          expect(
            userCollectionData,
            [
              [
                DocumentSnapshot(
                  doc: userDoc,
                  data: userData,
                ),
                DocumentSnapshot(
                  doc: userDoc2,
                  data: userData2,
                ),
              ],
              [],
            ],
          );

          expect(
            friendDocData,
            [
              DocumentSnapshot(
                doc: friendDoc,
                data: userData2,
              ),
              null,
            ],
          );

          expect(
            userCollectionData,
            [
              [
                DocumentSnapshot(
                  doc: userDoc,
                  data: userData,
                ),
                DocumentSnapshot(
                  doc: userDoc2,
                  data: userData2,
                ),
              ],
              [],
            ],
          );

          expect(
            friendCollectionData,
            [
              [
                DocumentSnapshot(
                  doc: friendDoc,
                  data: userData2,
                ),
              ],
              [],
            ],
          );
        },
      );
    },
  );

  group(
    'Replace collection',
    () {
      tearDown(() {
        Loon.clearAll();
      });

      test('Replaces all documents in the collection', () {
        final userDoc = TestUserModel.store.doc('1');
        final userDoc2 = TestUserModel.store.doc('2');

        final userData = TestUserModel('User 1');
        final userData2 = TestUserModel('User 2');

        userDoc.create(userData);
        userDoc2.create(userData2);

        expect(
          Loon.inspect()['store'],
          {
            "users": {
              "__values": {
                "1": DocumentSnapshot(
                  doc: userDoc,
                  data: userData,
                ),
                "2": DocumentSnapshot(
                  doc: userDoc2,
                  data: userData2,
                ),
              }
            }
          },
        );

        final updatedUser2 = TestUserModel('User 2 updated');
        final userDoc3 = TestUserModel.store.doc('3');
        final userData3 = TestUserModel('User 3');

        TestUserModel.store.replace([
          DocumentSnapshot(
            doc: userDoc2,
            data: updatedUser2,
          ),
          DocumentSnapshot(
            doc: userDoc3,
            data: userData3,
          ),
        ]);

        expect(
          Loon.inspect()['store'],
          {
            "users": {
              "__values": {
                "2": DocumentSnapshot(
                  doc: userDoc2,
                  data: updatedUser2,
                ),
                "3": DocumentSnapshot(
                  doc: userDoc3,
                  data: userData3,
                ),
              },
            }
          },
        );
      });

      test(
        "Broadcasts the expected change events",
        () async {
          final userDoc = TestUserModel.store.doc('1');
          final userDoc2 = TestUserModel.store.doc('2');

          final userData = TestUserModel('User 1');
          final userData2 = TestUserModel('User 2');

          final querySnaps =
              TestUserModel.store.streamChanges().take(2).toList();

          userDoc.create(userData);
          userDoc2.create(userData2);

          await asyncEvent();

          final updatedUser2 = TestUserModel('User 2 updated');
          final userDoc3 = TestUserModel.store.doc('3');
          final userData3 = TestUserModel('User 3');

          TestUserModel.store.replace([
            DocumentSnapshot(
              doc: userDoc2,
              data: updatedUser2,
            ),
            DocumentSnapshot(
              doc: userDoc3,
              data: userData3,
            ),
          ]);

          expect(
            await querySnaps,
            [
              [
                DocumentChangeSnapshot(
                  doc: userDoc,
                  data: userData,
                  event: EventTypes.added,
                  prevData: null,
                ),
                DocumentChangeSnapshot(
                  doc: userDoc2,
                  data: userData2,
                  event: EventTypes.added,
                  prevData: null,
                ),
              ],
              [
                DocumentChangeSnapshot(
                  doc: userDoc,
                  data: null,
                  event: EventTypes.removed,
                  prevData: userData,
                ),
                DocumentChangeSnapshot(
                  doc: userDoc2,
                  data: null,
                  event: EventTypes.removed,
                  prevData: userData2,
                ),
                DocumentChangeSnapshot(
                  doc: userDoc2,
                  data: updatedUser2,
                  event: EventTypes.added,
                  prevData: null,
                ),
                DocumentChangeSnapshot(
                  doc: userDoc3,
                  data: userData3,
                  event: EventTypes.added,
                  prevData: null,
                ),
              ]
            ],
          );
        },
      );
    },
  );

  group(
    'clearAll',
    () {
      tearDown(() {
        Loon.clearAll();
      });

      test('Clears all documents across all collections', () {
        final userDoc = TestUserModel.store.doc('1');
        final userDoc2 = TestUserModel.store.doc('2');

        final userData = TestUserModel('User 1');
        final userData2 = TestUserModel('User 2');

        userDoc.create(userData);
        userDoc2.create(userData2);

        expect(
          Loon.inspect()['store'],
          {
            "users": {
              "__values": {
                "1": DocumentSnapshot(
                  doc: userDoc,
                  data: userData,
                ),
                "2": DocumentSnapshot(
                  doc: userDoc2,
                  data: userData2,
                ),
              }
            }
          },
        );

        Loon.clearAll();

        expect(
          Loon.inspect()['store'],
          {},
        );
      });

      test(
        'Broadcasts the clear to observers',
        () async {
          final userDoc = TestUserModel.store.doc('1');
          final userData = TestUserModel('User 1');
          final userDocStream = userDoc.stream();
          final userCollectionStream = TestUserModel.store.stream();

          userDoc.create(userData);

          await asyncEvent();

          Loon.clearAll();

          final userDocStreamData = await userDocStream.take(3).toList();
          final userCollectionStreamData =
              await userCollectionStream.take(3).toList();

          expect(
            userDocStreamData,
            [
              null,
              DocumentSnapshot(
                doc: userDoc,
                data: userData,
              ),
              null,
            ],
          );

          expect(
            userCollectionStreamData,
            [
              [],
              [
                DocumentSnapshot(
                  doc: userDoc,
                  data: userData,
                ),
              ],
              [],
            ],
          );
        },
      );
    },
  );

  group('Root collection', () {
    tearDown(() {
      Loon.clearAll();
    });

    test('Writes documents successfully', () {
      final data = {"test": true};
      final rootDoc = Loon.doc('1');

      rootDoc.create(data);

      expect(
        Loon.inspect()['store'],
        {
          "ROOT": {
            "__values": {
              "1": DocumentSnapshot(
                doc: rootDoc,
                data: data,
              ),
            }
          }
        },
      );
    });

    test('Can be deleted successfully', () {
      final data = {"test": true};
      final rootDoc = Loon.doc('1');

      rootDoc.create(data);

      expect(
        Loon.inspect()['store'],
        {
          "ROOT": {
            "__values": {
              "1": DocumentSnapshot(
                doc: rootDoc,
                data: data,
              ),
            }
          }
        },
      );

      rootDoc.delete();

      expect(
        Loon.inspect()['store'],
        {},
      );
    });
  });

  group('Subcollections', () {
    tearDown(() {
      Loon.clearAll();
    });

    test('Read/Write documents successfully', () {
      final friendData = TestUserModel('Friend 1');
      final friendDoc = Loon.collection('users')
          .doc('1')
          .subcollection<TestUserModel>(
            'friends',
            fromJson: TestUserModel.fromJson,
            toJson: (snap) => snap.toJson(),
          )
          .doc('1');

      friendDoc.create(friendData);

      expect(
        Loon.inspect()['store'],
        {
          "users": {
            "1": {
              "friends": {
                "__values": {
                  "1": DocumentSnapshot(
                    doc: friendDoc,
                    data: friendData,
                  ),
                },
              },
            }
          }
        },
      );
    });
  });

  group('Hydration', () {
    tearDown(() {
      Loon.configure(persistor: null);
      Loon.clearAll();
    });

    test('Hydrates documents', () async {
      final userCollection = Loon.collection<TestUserModel>(
        'users',
        fromJson: TestUserModel.fromJson,
        toJson: (user) => user.toJson(),
      );
      final userDoc = userCollection.doc('1');
      final userData = TestUserModel('User 1');

      Loon.configure(
        persistor: TestPersistor(
          seedData: [
            DocumentSnapshot(
              doc: userDoc,
              data: userData,
            )
          ],
        ),
      );

      await Loon.hydrate();

      // The data is hydrated as Json
      expect(
        Loon.inspect()['store'],
        {
          "users": {
            "__values": {
              "1": DocumentSnapshot(
                doc: userDoc,
                data: userData.toJson(),
              ),
            }
          }
        },
      );

      // It is then de-serialized when it is first accessed.
      expect(
        userDoc.get(),
        DocumentSnapshot(
          doc: userDoc,
          data: userData,
        ),
      );

      // Afterwards first read, it is stored de-serialized.
      expect(
        Loon.inspect()['store'],
        {
          "users": {
            "__values": {
              "1": DocumentSnapshot(
                doc: userDoc,
                data: userData,
              ),
            }
          }
        },
      );
    });
  });

  group('dependencies', () {
    tearDown(() {
      Loon.clearAll();
    });

    test("Dependent changes should broadcast dependencies", () async {
      final usersCollection = Loon.collection('users');
      final postsCollection = Loon.collection<Json>(
        'posts',
        dependenciesBuilder: (snap) {
          if (snap.data['text'] == 'Post 1') {
            return {
              usersCollection.doc('1'),
            };
          }
          return {};
        },
      );

      final postDoc = postsCollection.doc('1');
      final postData = {"id": 1, "text": "Post 1"};
      final updatedPostData1 = {"text": "Post 1 updated"};
      final updatedPostData2 = {"text": "Post 1 updated again"};
      final userDoc = usersCollection.doc('1');
      final postsStream = postDoc.stream();

      postDoc.create(postData);

      await asyncEvent();

      expect(
        Loon.inspect()['dependencyStore'],
        {
          "dependencies": {
            "posts": {
              "1": {
                userDoc,
              },
            },
          },
          "dependents": {
            "users": {
              "1": {
                postDoc,
              }
            }
          },
        },
      );

      usersCollection.doc('1').create({
        "id": 1,
        "name": "User 1",
      });

      await asyncEvent();

      userDoc.update({
        "id": 1,
        "name": "User 1",
      });

      await asyncEvent();

      userDoc.delete();

      // Deleting the user doc should not alter the dependencies, as the post doc remains
      // dependent on the user doc, even when it is no longer in the store, since it could be added back later.
      expect(
        Loon.inspect()['dependencyStore'],
        {
          "dependencies": {
            "posts": {
              "1": {
                userDoc,
              },
            },
          },
          "dependents": {
            "users": {
              "1": {
                postDoc,
              },
            },
          },
        },
      );

      await asyncEvent();

      usersCollection.doc('1').create({
        "id": 1,
        "name": "User 1",
      });

      await asyncEvent();

      postDoc.update(updatedPostData1);

      // Now the post doc has been updated and is no longer dependent on the user doc.
      expect(
        Loon.inspect()['dependencyStore'],
        {
          "dependencies": {
            "posts": {
              "1": <dynamic>{},
            },
          },
          "dependents": {
            "users": {
              "1": <dynamic>{},
            }
          },
        },
      );

      await asyncEvent();

      userDoc.update({
        "id": 1,
        "name": "User 1 updated",
      });

      await asyncEvent();

      postDoc.update(updatedPostData2);

      final snaps = await postsStream.take(8).toList();

      // No post yet
      expect(snaps[0], null);
      // Post created
      expect(snaps[1]!.data, postData);
      // Rebroadcast post when user created
      expect(snaps[2]!.data, postData);
      // Rebroadcast post when user updated
      expect(snaps[3]!.data, postData);
      // Rebroadcast post when user deleted
      expect(snaps[4]!.data, postData);
      // Rebroadcast post when user re-added (ensures dependencies remain across deletion/re-creation)
      expect(snaps[5]!.data, postData);
      // Rebroadcast when post data is updated
      expect(snaps[6]!.data, updatedPostData1);
      // Skips the update to user doc, since the last update caused the user doc to be removed as a dependency.
      expect(snaps[7]!.data, updatedPostData2);
    });

    test("Cyclical dependencies do not cause infinite rebroadcasts", () async {
      final usersCollection = Loon.collection<TestUserModel>(
        'users',
        fromJson: TestUserModel.fromJson,
        toJson: (user) => user.toJson(),
        dependenciesBuilder: (snap) {
          return {
            Loon.collection('posts').doc('1'),
          };
        },
      );
      final postsCollection = Loon.collection(
        'posts',
        dependenciesBuilder: (snap) {
          return {
            usersCollection.doc('1'),
          };
        },
      );

      final userDoc = usersCollection.doc('1');
      final postDoc = postsCollection.doc('1');
      final userData = TestUserModel('Test user 1');
      final updatedUserData = TestUserModel('Test user 1 updated');
      final userObservable = userDoc.observe();
      final userStream = userObservable.stream();

      userDoc.create(userData);

      await asyncEvent();

      expect(
        Loon.inspect()['dependencyStore'],
        {
          "dependencies": {
            "users": {
              "1": {postDoc},
            },
          },
          "dependents": {
            "posts": {
              "1": {userDoc},
            }
          },
        },
      );

      postDoc.create({
        "id": 1,
        "name": "Post 1",
      });

      expect(
        Loon.inspect()['dependencyStore'],
        {
          "dependencies": {
            "users": {
              "1": {
                postDoc,
              }
            },
            "posts": {
              "1": {
                userDoc,
              }
            }
          },
          "dependents": {
            "posts": {
              "1": {
                userDoc,
              }
            },
            "users": {
              "1": {
                postDoc,
              }
            }
          },
        },
      );

      await asyncEvent();

      userDoc.update(updatedUserData);

      await asyncEvent();

      userObservable.dispose();

      expectLater(
        userStream,
        emitsInOrder([
          // First emits null when no user has been written.
          null,
          // Emits the initially created user.
          DocumentSnapshot(
            doc: userDoc,
            data: userData,
          ),
          // Emits the same user again when the post is updated. Infinite rebroadcasting
          // does not occur despite a cyclical dependency between the user and the post since
          // attempts to rebroadcast documents that are already pending broadcast are ignored.
          DocumentSnapshot(
            doc: userDoc,
            data: userData,
          ),
          // Emits the updated user.
          DocumentSnapshot(
            doc: userDoc,
            data: updatedUserData,
          ),
          emitsDone,
        ]),
      );
    });

    test("Deleting a collection clears its dependencies", () async {
      final usersCollection = Loon.collection('users');
      final friendsCollection = Loon.collection<TestUserModel>(
        'friends',
        dependenciesBuilder: (snap) {
          return {
            usersCollection.doc(snap.doc.id),
          };
        },
      );

      final userDoc = usersCollection.doc('1');
      final friendDoc = friendsCollection.doc('1');
      userDoc.create(TestUserModel('User 1'));
      friendDoc.create(TestUserModel('Friend 1'));

      await asyncEvent();

      expect(
        Loon.inspect()['dependencyStore'],
        {
          "dependencies": {
            "friends": {
              "1": {
                userDoc,
              }
            }
          },
          "dependents": {
            "users": {
              "1": {
                friendDoc,
              }
            }
          },
        },
      );

      friendsCollection.delete();

      await asyncEvent();

      expect(
        Loon.inspect()['dependencyStore'],
        {
          "dependencies": {},
          // The dependents are not cleared when a collection is cleared, instead
          // the dependents are lazily cleared when the dependent is updated.
          "dependents": {
            "users": {
              "1": {
                friendDoc,
              }
            }
          },
        },
      );

      userDoc.update(TestUserModel('User 1 updated'));

      await asyncEvent();

      expect(
        Loon.inspect()['dependencyStore'],
        {
          "dependencies": {},
          "dependents": {
            "users": {"1": <dynamic>{}}
          },
        },
      );
    });
  });
}
