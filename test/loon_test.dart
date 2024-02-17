import 'package:flutter/foundation.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:loon/loon.dart';

import 'models/test_persistor.dart';
import 'models/test_user_model.dart';

Future<void> asyncEvent() {
  return Future.delayed(const Duration(milliseconds: 1), () => null);
}

class DocumentSnapshotMatcher<T> extends Matcher {
  DocumentSnapshot<T?>? expected;
  late DocumentSnapshot<T?>? actual;
  DocumentSnapshotMatcher(this.expected);

  @override
  Description describe(Description description) {
    return description.add(
      "has expected document ID: ${expected?.id}, data: ${expected?.data}",
    );
  }

  @override
  Description describeMismatch(
    dynamic item,
    Description mismatchDescription,
    Map<dynamic, dynamic> matchState,
    bool verbose,
  ) {
    return mismatchDescription.add(
      "Expected: $item, Actual: ${matchState['actual']}",
    );
  }

  @override
  bool matches(actual, Map matchState) {
    this.actual = actual;

    final actualData = actual?.data;
    final expectedData = expected?.data;

    if (actual.doc.key != expected?.doc.key) {
      return false;
    }

    if (expectedData == null) {
      return actualData == null;
    }

    if (expectedData is Json) {
      return actualData is Json && mapEquals(actualData, expectedData);
    }

    if (expectedData is TestUserModel) {
      return actualData is TestUserModel && expectedData == actualData;
    }

    return false;
  }
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
          Loon.extract()['collectionStore'],
          {
            "users": {
              "1": DocumentSnapshotMatcher(
                DocumentSnapshot(
                  doc: userDoc,
                  data: user,
                ),
              ),
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
        Loon.extract()['collectionStore'],
        {
          "users": {
            "2": DocumentSnapshotMatcher(
              DocumentSnapshot(
                doc: userDoc,
                data: userJson,
              ),
            ),
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
        DocumentSnapshotMatcher(
          DocumentSnapshot(
            doc: userDoc,
            data: user,
          ),
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
        DocumentSnapshotMatcher(
          DocumentSnapshot(
            doc: userDoc,
            data: userJson,
          ),
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
        DocumentSnapshotMatcher(
          DocumentSnapshot(
            doc: userDoc,
            data: updatedUser,
          ),
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
        DocumentSnapshotMatcher(
          DocumentSnapshot(
            doc: userDoc,
            data: updatedUserJson,
          ),
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
        DocumentSnapshotMatcher(
          DocumentSnapshot(
            doc: userDoc,
            data: updatedUser,
          ),
        ),
      );
    });

    test('Modifinyg a non-existent document throws an error', () {
      final updatedUser = TestUserModel('User 1');
      final userDoc = TestUserModel.store.doc('1');

      expect(
        () => userDoc.modify((_) => updatedUser),
        throwsException,
      );
    });

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
        DocumentSnapshotMatcher(
          DocumentSnapshot(
            doc: userDoc,
            data: updatedUserJson,
          ),
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
        Loon.extract()['collectionStore'],
        {"users": {}},
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
          DocumentSnapshotMatcher(
            DocumentSnapshot(
              doc: userDoc,
              data: user,
            ),
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
          DocumentSnapshotMatcher(
            DocumentSnapshot(
              doc: userDoc,
              data: user,
            ),
          ),
          DocumentSnapshotMatcher(
            DocumentSnapshot(
              doc: userDoc,
              data: updatedUser,
            ),
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
        snaps[0].type,
        DocumentBroadcastTypes.added,
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
        snaps[1].type,
        DocumentBroadcastTypes.modified,
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
        DocumentSnapshotMatcher(
          DocumentSnapshot(
            doc: userDoc,
            data: user,
          ),
        ),
      );
    });
  });

  group('Stream documents', () {
    tearDown(() {
      Loon.clearAll();
    });

    test('Returns a stream of documents that satisfy the query', () async {
      final user = TestUserModel('User 1');
      final user2 = TestUserModel('User 2');
      final userDoc = TestUserModel.store.doc('1');
      final userDoc2 = TestUserModel.store.doc('2');

      userDoc.create(user);
      userDoc2.create(user2);

      final queryStream =
          TestUserModel.store.where((snap) => snap.id == '1').stream();

      final querySnap = await queryStream.first;

      expect(querySnap.length, 1);
      expect(
        querySnap.first,
        DocumentSnapshotMatcher(
          DocumentSnapshot(
            doc: userDoc,
            data: user,
          ),
        ),
      );
    });

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
      final firstSnap = querySnaps.first;
      final lastSnap = querySnaps.last;

      expect(firstSnap.length, 1);
      expect(
        firstSnap[0],
        DocumentSnapshotMatcher(
          DocumentSnapshot(
            doc: userDoc,
            data: user,
          ),
        ),
      );

      expect(lastSnap.isEmpty, true);
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

      final queryFuture = TestUserModel.store.streamChanges().take(2).toList();

      userDoc.create(user);
      userDoc2.create(user2);

      await asyncEvent();

      userDoc.update(updatedUser);

      final snaps = await queryFuture;

      expect(snaps[0].length, 2);

      expect(
        snaps[0].first.type,
        DocumentBroadcastTypes.added,
      );
      expect(
        snaps[0].first.data,
        user,
      );

      expect(
        snaps[0].last.type,
        DocumentBroadcastTypes.added,
      );
      expect(
        snaps[0].last.data,
        user2,
      );

      expect(snaps[1].length, 1);

      expect(
        snaps[1].first.type,
        DocumentBroadcastTypes.modified,
      );
      expect(
        snaps[1].first.prevData,
        user,
      );
      expect(
        snaps[1].first.data,
        updatedUser,
      );
    });

    test('Localizes broadcast event change types to the query', () async {
      final user = TestUserModel('User 1');
      final userDoc = TestUserModel.store.doc('1');

      final queryFuture = TestUserModel.store
          .where((snap) => snap.data.name == 'User 1 updated')
          .streamChanges()
          .take(1)
          .toList();

      userDoc.create(user);
      await asyncEvent();
      userDoc.update(TestUserModel('User 1 updated'));

      final snaps = await queryFuture;

      expect(snaps[0].length, 1);
      expect(
        snaps[0].first.type,
        // The global event is a [DocumentBroadcastTypes.modified] when the user is updated,
        // but to this query, it should be a [DocumentBroadcastTypes.added] event since previously
        // it was not included and now it is.
        DocumentBroadcastTypes.added,
      );
    });
  });

  group('Delete collection', () {
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
        Loon.extract()['collectionStore'],
        {
          "users": {
            "1": DocumentSnapshotMatcher(
              DocumentSnapshot(
                doc: userDoc,
                data: userData,
              ),
            ),
            "2": DocumentSnapshotMatcher(
              DocumentSnapshot(
                doc: userDoc2,
                data: userData2,
              ),
            ),
          }
        },
      );

      TestUserModel.store.delete();

      expect(
        Loon.extract()['collectionStore'],
        {},
      );
    });

    test('Deletes subcollections of the collection', () {
      final userDoc = TestUserModel.store.doc('1');
      final userDoc2 = TestUserModel.store.doc('2');

      final userData = TestUserModel('User 1');
      final userData2 = TestUserModel('User 2');

      final friendDoc =
          userDoc.subcollection<TestUserModel>('friends').doc('2');

      userDoc.create(userData);
      friendDoc.create(userData2);
      userDoc2.create(userData2);

      expect(
        Loon.extract()['collectionStore'],
        {
          "users": {
            "1": DocumentSnapshotMatcher(
              DocumentSnapshot(
                doc: userDoc,
                data: userData,
              ),
            ),
            "2": DocumentSnapshotMatcher(
              DocumentSnapshot(
                doc: userDoc2,
                data: userData2,
              ),
            ),
          },
          "users__1__friends": {
            "2": DocumentSnapshotMatcher(
              DocumentSnapshot(
                doc: friendDoc,
                data: userData2,
              ),
            ),
          }
        },
      );

      TestUserModel.store.delete();

      expect(
        Loon.extract()['collectionStore'],
        {},
      );
    });
  });

  group('Replace collection', () {
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
        Loon.extract()['collectionStore'],
        {
          "users": {
            "1": DocumentSnapshotMatcher(
              DocumentSnapshot(
                doc: userDoc,
                data: userData,
              ),
            ),
            "2": DocumentSnapshotMatcher(
              DocumentSnapshot(
                doc: userDoc2,
                data: userData2,
              ),
            ),
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
        Loon.extract()['collectionStore'],
        {
          "users": {
            "2": DocumentSnapshotMatcher(
              DocumentSnapshot(
                doc: userDoc2,
                data: updatedUser2,
              ),
            ),
            "3": DocumentSnapshotMatcher(
              DocumentSnapshot(
                doc: userDoc3,
                data: userData3,
              ),
            ),
          }
        },
      );
    });
  });

  group('clearAll', () {
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
        Loon.extract()['collectionStore'],
        {
          "users": {
            "1": DocumentSnapshotMatcher(
              DocumentSnapshot(
                doc: userDoc,
                data: userData,
              ),
            ),
            "2": DocumentSnapshotMatcher(
              DocumentSnapshot(
                doc: userDoc2,
                data: userData2,
              ),
            ),
          }
        },
      );

      Loon.clearAll();

      expect(
        Loon.extract()['collectionStore'],
        {},
      );
      expect(
        Loon.extract()['dependencyStore'],
        {
          'dependencies': {},
          'dependents': {},
        },
      );
    });
  });

  group('Root collection', () {
    tearDown(() {
      Loon.clearAll();
    });

    test('Writes documents successfully', () {
      final data = {"test": true};
      final rootDoc = Loon.doc('1');

      rootDoc.create(data);

      expect(
        Loon.extract()['collectionStore'],
        {
          "__ROOT__": {
            "1": DocumentSnapshotMatcher(
              DocumentSnapshot(
                doc: rootDoc,
                data: data,
              ),
            ),
          }
        },
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
          .subcollection<TestUserModel>('friends')
          .doc('1');

      friendDoc.create(friendData);

      expect(
        Loon.extract()['collectionStore'],
        {
          "users__1__friends": {
            "1": DocumentSnapshotMatcher(
              DocumentSnapshot(
                doc: friendDoc,
                data: friendData,
              ),
            ),
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

      expectLater(
        userDoc.stream(),
        emitsInOrder(
          [
            null,
            DocumentSnapshotMatcher(
              DocumentSnapshot(
                doc: userDoc,
                data: userData,
              ),
            ),
          ],
        ),
      );

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
        Loon.extract()['collectionStore'],
        {
          "users": {
            "1": DocumentSnapshotMatcher(
              DocumentSnapshot(
                doc: userDoc,
                data: userData.toJson(),
              ),
            ),
          }
        },
      );

      // It is then de-serialized when it is first accessed.
      expect(
        userDoc.get(),
        DocumentSnapshotMatcher(
          DocumentSnapshot(
            doc: userDoc,
            data: userData,
          ),
        ),
      );

      // Afterwards first read, it is stored de-serialized.
      expect(
        Loon.extract()['collectionStore'],
        {
          "users": {
            "1": DocumentSnapshotMatcher(
              DocumentSnapshot(
                doc: userDoc,
                data: userData,
              ),
            ),
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
        Loon.extract()['dependencyStore'],
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
        Loon.extract()['dependencyStore'],
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
        Loon.extract()['dependencyStore'],
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
        Loon.extract()['dependencyStore'],
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
        Loon.extract()['dependencyStore'],
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
          DocumentSnapshotMatcher(
            DocumentSnapshot(
              doc: userDoc,
              data: userData,
            ),
          ),
          // Emits the same user again when the post is updated. Infinite rebroadcasting
          // does not occur despite a cyclical dependency between the user and the post since
          // attempts to rebroadcast documents that are already pending broadcast are ignored.
          DocumentSnapshotMatcher(
            DocumentSnapshot(
              doc: userDoc,
              data: userData,
            ),
          ),
          // Emits the updated user.
          DocumentSnapshotMatcher(
            DocumentSnapshot(
              doc: userDoc,
              data: updatedUserData,
            ),
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
        Loon.extract()['dependencyStore'],
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
        Loon.extract()['dependencyStore'],
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
        Loon.extract()['dependencyStore'],
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
