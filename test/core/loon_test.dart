import 'package:fake_async/fake_async.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:loon/loon.dart';

import '../matchers/document_snapshot.dart';
import '../models/test_persistor.dart';
import '../models/test_user_model.dart';
import '../utils.dart';

void main() {
  group(
    'Loon',
    () {
      setUp(() {
        Loon.configure(persistor: null);
      });

      tearDown(() async {
        Loon.unsubscribe();
        await Loon.clearAll(broadcast: false);
      });

      group(
        'Document',
        () {
          group(
            'parent',
            () {
              test(
                'Returns the parent path',
                () {
                  expect(Loon.collection('users').doc('1').parent, 'users');
                  expect(
                    Loon.collection('users')
                        .doc('1')
                        .subcollection('posts')
                        .doc('2')
                        .parent,
                    'users__1__posts',
                  );
                },
              );
            },
          );

          group(
            'create',
            () {
              test(
                'Creates documents',
                () {
                  final usersCollection = Loon.collection('users');
                  final userDoc = usersCollection.doc('1');
                  final userDoc2 = usersCollection.doc('2');
                  final userDoc3 = usersCollection.doc('3');
                  final userDoc4 = usersCollection.doc('4');
                  final userDoc5 = TestUserModel.store.doc('5');
                  final userData = TestUserModel('5');
                  final userJson = {
                    "name": 'Test',
                  };

                  userDoc.create('Test');
                  userDoc2.create(2);
                  userDoc3.create(true);
                  userDoc4.create(userJson);
                  userDoc5.create(userData);

                  expect(
                    Loon.inspect()['store'],
                    {
                      "users": {
                        "__values": {
                          "1": DocumentSnapshot(doc: userDoc, data: 'Test'),
                          "2": DocumentSnapshot(doc: userDoc2, data: 2),
                          "3": DocumentSnapshot(doc: userDoc3, data: true),
                          "4": DocumentSnapshot(doc: userDoc4, data: userJson),
                          "5": DocumentSnapshot(doc: userDoc5, data: userData),
                        }
                      }
                    },
                  );
                },
              );

              test(
                  'Throws an error when creating a persisted document with non-serializable data without a serializer',
                  () {
                expect(
                  () => Loon.collection(
                    'users',
                    persistorSettings: const PersistorSettings(),
                  ).doc('1').create(TestUserModel('1')),
                  throwsA(
                    (e) =>
                        e is MissingSerializerException &&
                        e.toString() ==
                            'Missing serializer: Persisted document users__1 of type <Document<dynamic>> attempted to write snapshot of type <TestUserModel> without specifying a fromJson/toJson serializer pair.',
                  ),
                );

                expect(
                  () => Loon.collection(
                    'users',
                    persistorSettings: const PersistorSettings(),
                  ).doc('2').create([]),
                  throwsA(
                    (e) =>
                        e is MissingSerializerException &&
                        e.toString() ==
                            'Missing serializer: Persisted document users__2 of type <Document<dynamic>> attempted to write snapshot of type <List<dynamic>> without specifying a fromJson/toJson serializer pair.',
                  ),
                );
              });

              test(
                  'Does not throw an error when creating a persisted document with serializable data without a serializer',
                  () {
                final userDoc = Loon.collection(
                  'users',
                  persistorSettings: const PersistorSettings(),
                ).doc('1');

                expect(
                  userDoc.create('1'),
                  DocumentSnapshot(doc: userDoc, data: '1'),
                );

                userDoc.delete();

                expect(
                  userDoc.create(1),
                  DocumentSnapshot(doc: userDoc, data: 1),
                );

                userDoc.delete();

                expect(
                  userDoc.create(true),
                  DocumentSnapshot(doc: userDoc, data: true),
                );

                userDoc.delete();

                final userData = {
                  "name": "User 1",
                };
                expect(
                  userDoc.create(userData),
                  DocumentSnapshot(doc: userDoc, data: userData),
                );
              });

              test('Throws an error when creating duplicate documents', () {
                final user = TestUserModel('User 1');
                final userDoc = TestUserModel.store.doc('1');

                userDoc.create(user);

                expect(
                  () => userDoc.create(user),
                  throwsException,
                );
              });
            },
          );

          group(
            'get',
            () {
              test('Returns document snapshots', () {
                final userDoc = Loon.collection('users').doc('1');
                final userDoc2 = Loon.collection('users').doc('2');
                final userDoc3 = Loon.collection('users').doc('3');
                final userDoc4 = Loon.collection('users').doc('4');

                final userData = TestUserModel('User 1');
                final user2Data = {
                  "name": "User 2",
                };

                userDoc.create(userData);
                userDoc2.create(user2Data);
                userDoc3.create('3');
                userDoc4.create(true);

                expect(
                  userDoc.get(),
                  DocumentSnapshot(doc: userDoc, data: userData),
                );
                expect(
                  userDoc2.get(),
                  DocumentSnapshot(doc: userDoc2, data: user2Data),
                );
                expect(
                  userDoc3.get(),
                  DocumentSnapshot(doc: userDoc3, data: '3'),
                );
                expect(
                  userDoc4.get(),
                  DocumentSnapshot(doc: userDoc4, data: true),
                );
              });

              test('Returns serializable persisted document snapshots', () {
                final userDoc = TestUserModel.store.doc('1');
                final userDoc2 = Loon.collection('users').doc('2');
                final userDoc3 = Loon.collection('users').doc('3');
                final userDoc4 = Loon.collection('users').doc('4');

                final userData = TestUserModel('User 1');
                final user2Data = {
                  "name": "User 2",
                };

                userDoc.create(userData);
                userDoc2.create(user2Data);
                userDoc3.create('3');
                userDoc4.create(true);

                expect(
                  userDoc.get(),
                  DocumentSnapshot(doc: userDoc, data: userData),
                );
                expect(
                  userDoc2.get(),
                  DocumentSnapshot(doc: userDoc2, data: user2Data),
                );
                expect(
                  userDoc3.get(),
                  DocumentSnapshot(doc: userDoc3, data: '3'),
                );
                expect(
                  userDoc4.get(),
                  DocumentSnapshot(doc: userDoc4, data: true),
                );
              });

              test(
                'Throws an exception if the existing snapshot is incompatible with the new document type',
                () {
                  final usersCollection =
                      Loon.collection<TestUserModel>('users');

                  final userDoc = usersCollection.doc('1');

                  userDoc.create(TestUserModel('User 1'));

                  expect(
                    () => Loon.collection<int>('users').doc('1').get(),
                    throwsA(
                      (e) =>
                          e is DocumentTypeMismatchException &&
                          e.toString() ==
                              'Document type mismatch: Document users__1 of type <int> attempted to read snapshot of type: <TestUserModel>',
                    ),
                  );
                },
              );

              test(
                'Throws an exception if the new document does not specify a serialization pair for parsing the existing snapshot',
                () {
                  final usersCollection =
                      Loon.collection<TestUserModel>('users');

                  Loon.collection('users').doc('1').create({
                    "name": "User 1",
                  });

                  expect(
                    () => usersCollection.doc('1').get(),
                    throwsA(
                      (e) =>
                          e is MissingSerializerException &&
                          e.toString() ==
                              'Missing serializer: Persisted document users__1 of type <Document<TestUserModel>> attempted to read snapshot of type <_Map<String, String>> without specifying a fromJson/toJson serializer pair.',
                    ),
                  );
                },
              );

              test(
                'Reads a Json-typed collection without a fromJson serializer',
                () {
                  final userData = {"name": "User 1"};

                  Loon.collection('users').doc('1').create(userData);

                  expect(
                    Loon.collection<Json>('users').doc('1').get()?.data,
                    userData,
                  );
                },
              );
            },
          );

          group(
            'update',
            () {
              test(
                'Updates primitive documents',
                () {
                  final usersCollection = Loon.collection('users');
                  final userDoc = usersCollection.doc('1');

                  userDoc.create('Test');
                  userDoc.update('Test updated');

                  expect(
                    Loon.inspect()['store'],
                    {
                      "users": {
                        "__values": {
                          "1": DocumentSnapshot(
                              doc: userDoc, data: 'Test updated'),
                        }
                      }
                    },
                  );
                },
              );

              test('Updates serializable documents', () {
                final updatedUser = TestUserModel('User 1 updated');
                final userDoc = TestUserModel.store.doc('1');

                userDoc.create(TestUserModel('User 1'));
                userDoc.update(updatedUser);

                expect(
                  userDoc.get(),
                  DocumentSnapshot(doc: userDoc, data: updatedUser),
                );
              });

              test('Updates JSON documents', () {
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

              test(
                  'Throws an error when updating a document that does not exist',
                  () {
                final updatedUser = TestUserModel('User 1');
                final userDoc = TestUserModel.store.doc('1');

                expect(
                  () => userDoc.update(updatedUser),
                  throwsException,
                );
              });

              test(
                  'Throws an error when updating a persisted document without a serializer',
                  () {
                expect(
                  () => Loon.collection(
                    'users',
                    persistorSettings: const PersistorSettings(),
                  ).doc('1').update(TestUserModel('1')),
                  throwsException,
                );
              });

              test(
                  'Allows updating an existing document to a different data type',
                  () {
                final usersCollection = Loon.collection<TestUserModel>(
                  'users',
                  fromJson: TestUserModel.fromJson,
                  toJson: (snap) => snap.toJson(),
                );
                final numericUsersCollection = Loon.collection<int>('users');
                final userData = TestUserModel('User 1');

                usersCollection.doc('1').create(userData);

                // It is a valid case to update a document from one data type (in this case TestUserModel)
                // to another type (int).
                numericUsersCollection.doc('1').update(10);

                expect(
                  numericUsersCollection.doc('1').get(),
                  DocumentSnapshotMatcher(
                    DocumentSnapshot(
                      doc: numericUsersCollection.doc('1'),
                      data: 10,
                    ),
                  ),
                );
              });

              test('Skips broadcasting unchanged data by default', () {
                fakeAsync((async) {
                  final userDoc = Loon.collection('users').doc('1');
                  final user = TestUserModel('User 1');
                  final updatedUser = TestUserModel('User 1 updated');

                  userDoc.create(user);

                  flushBroadcasts(async);

                  final events = <DocumentSnapshot?>[];
                  final sub = userDoc.stream().listen(events.add);
                  flushBroadcasts(async);

                  userDoc.update(user);

                  flushBroadcasts(async);

                  userDoc.update(updatedUser);

                  flushBroadcasts(async);

                  expect(
                    events,
                    [
                      DocumentSnapshot(doc: userDoc, data: user),
                      DocumentSnapshot(doc: userDoc, data: updatedUser),
                    ],
                  );

                  sub.cancel();
                  async.flushMicrotasks();
                });
              });
            },
          );

          group(
            'modify',
            () {
              test(
                'Modifies the document',
                () {
                  final userDoc = TestUserModel.store.doc('1');
                  final user = TestUserModel('User 1');
                  final userUpdated = TestUserModel('User 1 updated');

                  userDoc.create(user);

                  expect(
                    userDoc.modify((_) => userUpdated),
                    DocumentSnapshot(
                      doc: userDoc,
                      data: userUpdated,
                    ),
                  );
                },
              );

              test('Modifies documents with a serializer', () {
                final updatedUser = TestUserModel('User 1 updated');
                final userDoc = TestUserModel.store.doc('1');

                userDoc.create(TestUserModel('User 1'));
                userDoc.modify((userSnap) => updatedUser);

                expect(
                  userDoc.get(),
                  DocumentSnapshot(doc: userDoc, data: updatedUser),
                );
              });

              test('Modifies JSON documents', () {
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

              test(
                  'Throws an error when modifying non-primitive documents without a serializer',
                  () {
                Loon.collection(
                  'users',
                  persistorSettings: const PersistorSettings(),
                  fromJson: TestUserModel.fromJson,
                  toJson: (snap) => snap.toJson(),
                ).doc('1').create(TestUserModel('1'));

                expect(
                  () => Loon.collection(
                    'users',
                    persistorSettings: const PersistorSettings(),
                  ).doc('1').modify((userSnap) => TestUserModel('1')),
                  throwsA(
                    (e) =>
                        e.toString() ==
                        'Missing serializer: Persisted document users__1 of type <Document<dynamic>> attempted to write snapshot of type <TestUserModel> without specifying a fromJson/toJson serializer pair.',
                  ),
                );
              });

              test(
                  'Throws an error when modifying a document that does not exist',
                  () {
                final userDoc = TestUserModel.store.doc('1');

                expect(
                  () => userDoc.modify(
                      (snap) => snap.data.copyWith(name: 'Updated User 1')),
                  throwsException,
                );
              });
            },
          );

          group(
            'delete',
            () {
              test(
                'Deletes primitive documents',
                () {
                  final usersCollection = Loon.collection('users');
                  final userDoc = usersCollection.doc('1');

                  userDoc.create('Test');
                  userDoc.delete();

                  expect(
                    Loon.inspect()['store'],
                    {},
                  );
                },
              );

              test('Deletes documents with a serializer', () {
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

              test(
                'Deletes subcollection documents',
                () {
                  final user = TestUserModel('User 1');
                  final userDoc = TestUserModel.store.doc('1');

                  final friend = TestUserModel('Friend 1');
                  final friendDoc = userDoc.subcollection('friends').doc('1');

                  userDoc.create(user);
                  friendDoc.create(friend);

                  expect(friendDoc.exists(), true);

                  userDoc.delete();

                  expect(friendDoc.exists(), false);

                  expect(
                    Loon.inspect()["store"],
                    {},
                  );
                },
              );

              test(
                'Deletes subcollection documents under a non-existent document',
                () {
                  final userDoc = TestUserModel.store.doc('1');
                  final friend = TestUserModel('Friend 1');
                  final friendDoc = userDoc.subcollection('friends').doc('1');

                  friendDoc.create(friend);

                  expect(friendDoc.exists(), true);

                  // Even though the user does not exist, it should still delete all the existing
                  // data under the user document path.
                  userDoc.delete();

                  expect(friendDoc.exists(), false);

                  expect(
                    Loon.inspect()["store"],
                    {},
                  );
                },
              );
            },
          );

          group('subcollection', () {
            test('reads/writes documents successfully', () {
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

          group(
            'rebroadcast',
            () {
              test(
                'rebroadcasts the document to its stream listeners',
                () {
                  fakeAsync((async) {
                    final usersCollection = Loon.collection('users');
                    final userDoc = usersCollection.doc('1');

                    final events = <DocumentSnapshot?>[];
                    final sub = userDoc.stream().listen(events.add);
                    flushBroadcasts(async);

                    userDoc.create('Test');
                    flushBroadcasts(async);

                    userDoc.rebroadcast();
                    flushBroadcasts(async);

                    expect(
                      events,
                      [
                        null,
                        DocumentSnapshot(doc: userDoc, data: 'Test'),
                        DocumentSnapshot(doc: userDoc, data: 'Test'),
                      ],
                    );

                    sub.cancel();
                    async.flushMicrotasks();
                  });
                },
              );
            },
          );

          group(
            'rebuildDependencies',
            () {
              test(
                "Rebuilds the document's dependencies",
                () {
                  fakeAsync((async) {
                    bool hasDependencies = false;

                    final usersCollection = Loon.collection<String>(
                      'users',
                      dependenciesBuilder: (snap) {
                        if (hasDependencies) {
                          return {
                            Loon.collection('friends').doc(snap.id),
                          };
                        }

                        return {};
                      },
                    );

                    final userDoc = usersCollection.doc('1');
                    userDoc.create('User 1');
                    flushBroadcasts(async);

                    final events = <DocumentSnapshot<String>?>[];
                    final sub = userDoc.stream().listen(events.add);
                    flushBroadcasts(async);

                    final friendDoc =
                        Loon.collection('friends').doc(userDoc.id);
                    // This event is ignored since the user does not yet depend on the friend document.
                    friendDoc.create('Friend 1');

                    userDoc.update('User 1 updated');
                    flushBroadcasts(async);

                    hasDependencies = true;

                    userDoc.rebuildDependencies();

                    // This event causes a rebroadcast of the user, as they now depend on the friend document.
                    friendDoc.update('Friend 1 updated');
                    flushBroadcasts(async);

                    expect(
                      events,
                      [
                        DocumentSnapshot(doc: userDoc, data: 'User 1'),
                        DocumentSnapshot(doc: userDoc, data: 'User 1 updated'),
                        DocumentSnapshot(doc: userDoc, data: 'User 1 updated'),
                      ],
                    );

                    sub.cancel();
                    async.flushMicrotasks();
                  });
                },
              );
            },
          );
        },
      );

      group(
        'ObservableDocument',
        () {
          group(
            'stream',
            () {
              test('Returns a stream of document snapshots', () {
                fakeAsync((async) {
                  final user = TestUserModel('User 1');
                  final userUpdated = TestUserModel('User 1 updated');
                  final userDoc = TestUserModel.store.doc('1');
                  final events = <DocumentSnapshot<TestUserModel>?>[];
                  final sub = userDoc.stream().listen(events.add);

                  flushBroadcasts(async);
                  userDoc.create(user);
                  flushBroadcasts(async);
                  userDoc.update(userUpdated);
                  flushBroadcasts(async);
                  userDoc.delete();
                  flushBroadcasts(async);

                  expect(
                    events,
                    [
                      null,
                      DocumentSnapshot(doc: userDoc, data: user),
                      DocumentSnapshot(doc: userDoc, data: userUpdated),
                      null,
                    ],
                  );

                  sub.cancel();
                  async.flushMicrotasks();
                });
              });
            },
          );

          group(
            'streamChanges',
            () {
              test('Returns a stream of document change snapshots', () {
                fakeAsync((async) {
                  final userDoc = TestUserModel.store.doc('1');
                  final userData = TestUserModel('User 1');
                  final userDataUpdated = TestUserModel('User 1 updated');
                  final userObs = userDoc.observe();
                  final events = <DocumentChangeSnapshot<TestUserModel>>[];
                  final sub = userObs.streamChanges().listen(events.add);

                  flushBroadcasts(async);
                  userDoc.create(userData);
                  flushBroadcasts(async);
                  userDoc.update(userDataUpdated);
                  flushBroadcasts(async);

                  expect(
                    events,
                    [
                      DocumentChangeSnapshot(
                        doc: userObs,
                        data: userData,
                        prevData: null,
                        event: BroadcastEvents.added,
                      ),
                      DocumentChangeSnapshot(
                        doc: userObs,
                        data: userDataUpdated,
                        prevData: userData,
                        event: BroadcastEvents.modified,
                      ),
                    ],
                  );

                  sub.cancel();
                  async.flushMicrotasks();
                });
              });
            },
          );

          test(
            "Maintains its dependency cache correctly",
            () {
              fakeAsync((async) {
                final usersCollection = Loon.collection('users');
                final postsCollection = Loon.collection<Json>(
                  'posts',
                  dependenciesBuilder: (snap) {
                    if (snap.data['userId'] != null) {
                      return {
                        usersCollection.doc(snap.data['userId'].toString()),
                      };
                    }
                    return null;
                  },
                );

                final postDoc = postsCollection.doc('1');
                final postData = {"id": 1, "text": "Post 1", "userId": 1};
                final postData2 = {"id": 1, "text": "Post 1 updated"};
                final postData3 = {
                  "id": 1,
                  "text": "Post 1 updated",
                  "userId": 3
                };
                final postObs = postDoc.observe();

                postDoc.create(postData);
                flushBroadcasts(async);

                // After creating the post document, it should have added its user dependency into the observable's
                // dep tree.
                expect(postObs.inspect(), {
                  "deps": {
                    "__ref": 1,
                    "users": {
                      "__ref": 1,
                      "1": 1,
                    },
                  },
                });

                postDoc.update(postData2);
                flushBroadcasts(async);

                // After updating the document, it should have removed the user dependency from the observable's
                // dep tree.
                expect(postObs.inspect(), {
                  "deps": {},
                });

                postDoc.update(postData3);
                flushBroadcasts(async);

                // The observable should have been updated to have a user dependency again.
                expect(postObs.inspect(), {
                  "deps": {
                    "__ref": 1,
                    "users": {
                      "__ref": 1,
                      "3": 1,
                    },
                  },
                });

                postsCollection.delete();
                flushBroadcasts(async);

                // After deleting the posts collection, observable should have cleared its dependencies.
                expect(postObs.inspect(), {"deps": {}});
              });
            },
          );

          test(
            'Invalidates its cached value when the document is updated',
            () {
              fakeAsync((async) {
                final usersCollection = Loon.collection(
                  'users',
                  fromJson: TestUserModel.fromJson,
                  toJson: (user) => user.toJson(),
                );

                final userDoc = usersCollection.doc('1');
                final userData = TestUserModel('User 1');
                final userDataUpdated = TestUserModel('User 1 updated');

                userDoc.create(userData);
                final userObs = userDoc.observe();

                flushBroadcasts(async);

                DocumentSnapshot<TestUserModel>? snap = userObs.get();

                // The observable's value is cached and is not recomputed unless invalidated by
                // a change to its document.
                expect(identical(snap, userObs.get()), true);
                expect(snap, DocumentSnapshot(doc: userDoc, data: userData));

                userDoc.update(userDataUpdated);
                snap = userObs.get();

                // The updated document has not been broadcast yet, however the observable's cached
                // value has been invalidated by the update to its documents and should return
                // an up-to-date recalculated value.
                expect(
                  snap,
                  DocumentSnapshot(doc: userDoc, data: userDataUpdated),
                );
                flushBroadcasts(async);
              });
            },
          );
        },
      );

      group(
        'Collection',
        () {
          group(
            'delete',
            () {
              test('Deletes all documents in the collection', () {
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
                        "1": DocumentSnapshot(doc: userDoc, data: userData),
                        "2": DocumentSnapshot(doc: userDoc2, data: userData2),
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
                () {
                  fakeAsync((async) {
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
                    flushBroadcasts(async);

                    final userDocData = <DocumentSnapshot<TestUserModel>?>[];
                    final userCollectionData =
                        <List<DocumentSnapshot<TestUserModel>>>[];
                    final friendDocData = <DocumentSnapshot<TestUserModel>?>[];
                    final friendCollectionData =
                        <List<DocumentSnapshot<TestUserModel>>>[];
                    final userDocSub = userDoc.stream().listen(userDocData.add);
                    final userCollectionSub = TestUserModel.store
                        .stream()
                        .listen(userCollectionData.add);
                    final friendDocSub =
                        friendDoc.stream().listen(friendDocData.add);
                    final friendCollectionSub = userDoc
                        .subcollection<TestUserModel>('friends')
                        .stream()
                        .listen(friendCollectionData.add);
                    flushBroadcasts(async);

                    TestUserModel.store.delete();
                    flushBroadcasts(async);

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

                    userDocSub.cancel();
                    userCollectionSub.cancel();
                    friendDocSub.cancel();
                    friendCollectionSub.cancel();
                    async.flushMicrotasks();
                  });
                },
              );
            },
          );

          group(
            'replace',
            () {
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
                () {
                  fakeAsync((async) {
                    final userDoc = TestUserModel.store.doc('1');
                    final userDoc2 = TestUserModel.store.doc('2');

                    final userData = TestUserModel('User 1');
                    final userData2 = TestUserModel('User 2');

                    final querySnaps =
                        <List<DocumentChangeSnapshot<TestUserModel>>>[];
                    final sub = TestUserModel.store
                        .streamChanges()
                        .listen(querySnaps.add);

                    userDoc.create(userData);
                    userDoc2.create(userData2);

                    flushBroadcasts(async);

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
                    flushBroadcasts(async);

                    expect(
                      querySnaps,
                      [
                        [
                          DocumentChangeSnapshot(
                            doc: userDoc,
                            data: userData,
                            event: BroadcastEvents.added,
                            prevData: null,
                          ),
                          DocumentChangeSnapshot(
                            doc: userDoc2,
                            data: userData2,
                            event: BroadcastEvents.added,
                            prevData: null,
                          ),
                        ],
                        [
                          DocumentChangeSnapshot(
                            doc: userDoc,
                            data: null,
                            event: BroadcastEvents.removed,
                            prevData: userData,
                          ),
                          DocumentChangeSnapshot(
                            doc: userDoc2,
                            data: null,
                            event: BroadcastEvents.removed,
                            prevData: userData2,
                          ),
                          DocumentChangeSnapshot(
                            doc: userDoc2,
                            data: updatedUser2,
                            event: BroadcastEvents.added,
                            prevData: null,
                          ),
                          DocumentChangeSnapshot(
                            doc: userDoc3,
                            data: userData3,
                            event: BroadcastEvents.added,
                            prevData: null,
                          ),
                        ]
                      ],
                    );

                    sub.cancel();
                    async.flushMicrotasks();
                  });
                },
              );
            },
          );
        },
      );

      group(
        'Query',
        () {
          group(
            'get',
            () {
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
                  DocumentSnapshot(doc: userDoc, data: user),
                );
              });
            },
          );
        },
      );

      group(
        'ObservableQuery',
        () {
          group('stream', () {
            test(
              'Returns a stream of updates to the query',
              () {
                fakeAsync((async) {
                  final user = TestUserModel('User 1');
                  final userUpdated = TestUserModel('User 1 updated');
                  final user2 = TestUserModel('User 2');
                  final userDoc = TestUserModel.store.doc('1');
                  final userDoc2 = TestUserModel.store.doc('2');

                  final querySnaps = <List<DocumentSnapshot<TestUserModel>>>[];
                  final sub = TestUserModel.store
                      .where((snap) => snap.id == '1')
                      .stream()
                      .listen(querySnaps.add);

                  flushBroadcasts(async);
                  userDoc.create(user);
                  userDoc2.create(user2);

                  flushBroadcasts(async);
                  userDoc.update(userUpdated);
                  flushBroadcasts(async);
                  userDoc.delete();
                  flushBroadcasts(async);
                  userDoc.create(user);
                  flushBroadcasts(async);
                  TestUserModel.store.delete();
                  flushBroadcasts(async);

                  expect(
                    querySnaps,
                    [
                      // No data
                      [],
                      // User 1 created
                      [
                        DocumentSnapshot(doc: userDoc, data: user),
                      ],
                      // User 1 updated
                      [
                        DocumentSnapshot(doc: userDoc, data: userUpdated),
                      ],
                      // User 1 deleted
                      [],
                      // User 1 recreated
                      [
                        DocumentSnapshot(doc: userDoc, data: user),
                      ],
                      // User collection deleted
                      [],
                    ],
                  );

                  sub.cancel();
                  async.flushMicrotasks();
                });
              },
            );

            test(
              'Handles the scenario where a collection is removed and written to in the same task',
              () {
                fakeAsync((async) {
                  final user = TestUserModel('User 1');
                  final user2 = TestUserModel('User 2');
                  final userDoc = TestUserModel.store.doc('1');
                  final userDoc2 = TestUserModel.store.doc('2');

                  userDoc.create(user);
                  userDoc2.create(user2);

                  flushBroadcasts(async);

                  final querySnaps = <List<DocumentSnapshot<TestUserModel>>>[];
                  final sub =
                      TestUserModel.store.stream().listen(querySnaps.add);
                  flushBroadcasts(async);

                  TestUserModel.store.delete();
                  userDoc.create(user);
                  flushBroadcasts(async);

                  expect(
                    querySnaps,
                    [
                      [
                        DocumentSnapshot(doc: userDoc, data: user),
                        DocumentSnapshot(doc: userDoc2, data: user2),
                      ],
                      // Rather than emitting an empty result set when the store is deleted,
                      // the stream batches changes in the same task together and emits a single
                      // update with the re-created user.
                      [
                        DocumentSnapshot(doc: userDoc, data: user),
                      ],
                    ],
                  );

                  sub.cancel();
                  async.flushMicrotasks();
                });
              },
            );
          });

          group(
            'streamChanges',
            () {
              test('Returns a stream of changes to the query', () {
                fakeAsync((async) {
                  final user = TestUserModel('User 1');
                  final user2 = TestUserModel('User 2');
                  final userDoc = TestUserModel.store.doc('1');
                  final userDoc2 = TestUserModel.store.doc('2');
                  final updatedUser = TestUserModel('User 1 updated');

                  final events =
                      <List<DocumentChangeSnapshot<TestUserModel>>>[];
                  final sub =
                      TestUserModel.store.streamChanges().listen(events.add);

                  flushBroadcasts(async);
                  userDoc.create(user);
                  userDoc2.create(user2);
                  flushBroadcasts(async);
                  userDoc.update(updatedUser);
                  flushBroadcasts(async);
                  userDoc.delete();
                  flushBroadcasts(async);
                  TestUserModel.store.delete();
                  flushBroadcasts(async);

                  expect(
                    events,
                    [
                      // Create documents
                      [
                        DocumentChangeSnapshot(
                          doc: userDoc,
                          data: user,
                          event: BroadcastEvents.added,
                          prevData: null,
                        ),
                        DocumentChangeSnapshot(
                          doc: userDoc2,
                          data: user2,
                          event: BroadcastEvents.added,
                          prevData: null,
                        ),
                      ],
                      // Update document
                      [
                        DocumentChangeSnapshot(
                          doc: userDoc,
                          data: updatedUser,
                          event: BroadcastEvents.modified,
                          prevData: user,
                        ),
                      ],
                      // Remove document
                      [
                        DocumentChangeSnapshot(
                          doc: userDoc,
                          data: null,
                          event: BroadcastEvents.removed,
                          prevData: updatedUser,
                        ),
                      ],
                      // Delete user collection
                      [
                        DocumentChangeSnapshot(
                          doc: userDoc2,
                          data: null,
                          event: BroadcastEvents.removed,
                          prevData: user2,
                        ),
                      ]
                    ],
                  );

                  sub.cancel();
                  async.flushMicrotasks();
                });
              });

              test('Localizes broadcast event types to the query', () {
                fakeAsync((async) {
                  final user = TestUserModel('User 1');
                  final userDoc = TestUserModel.store.doc('1');

                  final changeSnaps =
                      <List<DocumentChangeSnapshot<TestUserModel>>>[];
                  final sub = TestUserModel.store
                      .where((snap) => snap.data.name == 'User 1 updated')
                      .streamChanges()
                      .listen(changeSnaps.add);

                  userDoc.create(user);
                  flushBroadcasts(async);
                  final updatedUser = TestUserModel('User 1 updated');
                  userDoc.update(updatedUser);
                  flushBroadcasts(async);

                  expect(
                    changeSnaps,
                    [
                      [
                        DocumentChangeSnapshot(
                          doc: userDoc,
                          data: updatedUser,
                          // The global event is a [BroadcastBroadcastEvents.modified] when the user is updated,
                          // but to this query, it should be a [BroadcastBroadcastEvents.added] event since previously
                          // it was not included and now it is.
                          event: BroadcastEvents.added,
                          prevData: null,
                        ),
                      ],
                    ],
                  );

                  sub.cancel();
                  async.flushMicrotasks();
                });
              });

              test(
                'Handles the scenario where a collection is removed and written to in the same task',
                () {
                  fakeAsync((async) {
                    final user = TestUserModel('User 1');
                    final user2 = TestUserModel('User 2');
                    final userDoc = TestUserModel.store.doc('1');
                    final userDoc2 = TestUserModel.store.doc('2');

                    final changeSnaps =
                        <List<DocumentChangeSnapshot<TestUserModel>>>[];
                    final sub = TestUserModel.store
                        .streamChanges()
                        .listen(changeSnaps.add);

                    userDoc.create(user);
                    userDoc2.create(user2);

                    flushBroadcasts(async);

                    TestUserModel.store.delete();
                    userDoc.create(user);
                    flushBroadcasts(async);

                    expect(
                      changeSnaps,
                      [
                        [
                          DocumentChangeSnapshot(
                            doc: userDoc,
                            data: user,
                            prevData: null,
                            event: BroadcastEvents.added,
                          ),
                          DocumentChangeSnapshot(
                            doc: userDoc2,
                            data: user2,
                            prevData: null,
                            event: BroadcastEvents.added,
                          )
                        ],
                        // The deletion of the collection and the re-creation of the document
                        // are batched together into a single change event that includes the correct events
                        // for each document.
                        [
                          DocumentChangeSnapshot(
                            doc: userDoc,
                            data: null,
                            prevData: user,
                            event: BroadcastEvents.removed,
                          ),
                          DocumentChangeSnapshot(
                            doc: userDoc2,
                            data: null,
                            prevData: user2,
                            event: BroadcastEvents.removed,
                          ),
                          DocumentChangeSnapshot(
                            doc: userDoc,
                            data: user,
                            prevData: null,
                            event: BroadcastEvents.added,
                          ),
                        ],
                      ],
                    );

                    sub.cancel();
                    async.flushMicrotasks();
                  });
                },
              );

              test(
                'Discards changes that occur to a collection in the same task as a subsequent deletion of that collection',
                () {
                  fakeAsync((async) {
                    final user = TestUserModel('User 1');
                    final user2 = TestUserModel('User 2');
                    final userDoc = TestUserModel.store.doc('1');
                    final userDoc2 = TestUserModel.store.doc('2');

                    final changeSnaps =
                        <List<DocumentChangeSnapshot<TestUserModel>>>[];
                    final sub = TestUserModel.store
                        .streamChanges()
                        .listen(changeSnaps.add);

                    userDoc.create(user);
                    userDoc2.create(user2);

                    flushBroadcasts(async);

                    userDoc.update(TestUserModel('User 1 updated'));
                    TestUserModel.store.delete();
                    flushBroadcasts(async);

                    expect(
                      changeSnaps,
                      [
                        [
                          DocumentChangeSnapshot(
                            doc: userDoc,
                            data: user,
                            prevData: null,
                            event: BroadcastEvents.added,
                          ),
                          DocumentChangeSnapshot(
                            doc: userDoc2,
                            data: user2,
                            prevData: null,
                            event: BroadcastEvents.added,
                          )
                        ],
                        [
                          DocumentChangeSnapshot(
                            doc: userDoc,
                            data: null,
                            prevData: user,
                            event: BroadcastEvents.removed,
                          ),
                          DocumentChangeSnapshot(
                            doc: userDoc2,
                            data: null,
                            prevData: user2,
                            event: BroadcastEvents.removed,
                          ),
                        ],
                      ],
                    );

                    sub.cancel();
                    async.flushMicrotasks();
                  });
                },
              );
            },
          );

          test(
            "Maintains its dependency/snapshot caches correctly",
            () {
              fakeAsync((async) {
                final usersCollection = Loon.collection('users');
                final postsCollection = Loon.collection<Json>(
                  'posts',
                  dependenciesBuilder: (snap) {
                    if (snap.data['userId'] != null) {
                      return {
                        usersCollection.doc(snap.data['userId'].toString()),
                      };
                    }
                    return null;
                  },
                );

                final postDoc = postsCollection.doc('1');
                final post1Data = {"id": 1, "text": "Post 1", "userId": 1};
                final post1Data2 = {"id": 1, "text": "Post 1 updated"};
                final post1Data3 = {
                  "id": 1,
                  "text": "Post 1 updated",
                  "userId": 3
                };
                final postDoc2 = postsCollection.doc('2');
                final post2Data = {"id": 2, "text": "Post 2", "userId": 2};
                final userDoc = usersCollection.doc('1');
                final userDoc2 = usersCollection.doc('2');
                final userDoc3 = usersCollection.doc('3');
                final postsObs = postsCollection.toQuery().observe();

                postDoc.create(post1Data);
                flushBroadcasts(async);

                // After creating the post document, the query should have a global and document level
                // dependency.
                expect(postsObs.inspect(), {
                  "deps": {
                    "__ref": 1,
                    "users": {
                      "__ref": 1,
                      "1": 1,
                    },
                  },
                  "docDeps": {
                    postDoc: {
                      userDoc,
                    },
                  },
                  "docSnaps": {
                    postDoc: DocumentSnapshot(doc: postDoc, data: post1Data),
                  }
                });

                postDoc.update(post1Data2);
                flushBroadcasts(async);

                // After updating the document, it should have removed the user dependency from the observable's
                // dep tree and document level dependency cache.
                expect(postsObs.inspect(), {
                  "deps": {},
                  "docDeps": {},
                  "docSnaps": {
                    postDoc: DocumentSnapshot(doc: postDoc, data: post1Data2),
                  }
                });

                postDoc.update(post1Data);
                postDoc2.create(post2Data);
                flushBroadcasts(async);

                // After updating the first post to have a user dependency again, and creating a second
                // post with another user dependency, the query's dependencies should have two entries.
                expect(postsObs.inspect(), {
                  "deps": {
                    "__ref": 2,
                    "users": {
                      "__ref": 2,
                      "1": 1,
                      "2": 1,
                    },
                  },
                  "docDeps": {
                    postDoc: {
                      userDoc,
                    },
                    postDoc2: {
                      userDoc2,
                    },
                  },
                  "docSnaps": {
                    postDoc: DocumentSnapshot(doc: postDoc, data: post1Data),
                    postDoc2: DocumentSnapshot(doc: postDoc2, data: post2Data),
                  }
                });

                postDoc.update(post1Data3);
                flushBroadcasts(async);

                // After updating the post to be dependent on a different user, the observable query
                // should have removed the reference to the previous user (user 1) and replaced it with the
                // dependency on user 3.
                expect(postsObs.inspect(), {
                  "deps": {
                    "__ref": 2,
                    "users": {
                      "__ref": 2,
                      "2": 1,
                      "3": 1,
                    },
                  },
                  "docDeps": {
                    postDoc: {
                      userDoc3,
                    },
                    postDoc2: {
                      userDoc2,
                    },
                  },
                  "docSnaps": {
                    postDoc: DocumentSnapshot(doc: postDoc, data: post1Data3),
                    postDoc2: DocumentSnapshot(doc: postDoc2, data: post2Data),
                  }
                });

                postsCollection.delete();
                flushBroadcasts(async);

                // After deleting the posts collection, the query should have cleared its global
                // and document level dependencies.
                expect(
                  postsObs.inspect(),
                  {"deps": {}, "docDeps": {}, "docSnaps": {}},
                );
              });
            },
          );

          test(
            'Invalidates its cached value when its collection is updated',
            () {
              fakeAsync((async) {
                final usersCollection = Loon.collection(
                  'users',
                  fromJson: TestUserModel.fromJson,
                  toJson: (user) => user.toJson(),
                );

                final userDoc = usersCollection.doc('1');
                final userDoc2 = usersCollection.doc('2');
                final userData = TestUserModel('User 1');
                final userDataUpdated = TestUserModel('User 1 updated');
                final user2Data = TestUserModel('User 2');

                userDoc.create(userData);
                userDoc2.create(user2Data);
                final usersObs = usersCollection.observe();

                flushBroadcasts(async);

                List<DocumentSnapshot<TestUserModel>> snaps = usersObs.get();

                // The observable's value is cached and is not recomputed unless invalidated by
                // a change to its collection.
                expect(identical(snaps, usersObs.get()), true);
                expect(
                  snaps,
                  [
                    DocumentSnapshot(doc: userDoc, data: userData),
                    DocumentSnapshot(doc: userDoc2, data: user2Data),
                  ],
                );

                userDoc.update(userDataUpdated);
                snaps = usersObs.get();

                // The updated document has not been broadcast yet, however the observable's cached
                // value has been invalidated by the update to one of its documents and should return
                // an up-to-date recalculated value.
                expect(snaps, [
                  DocumentSnapshot(doc: userDoc, data: userDataUpdated),
                  DocumentSnapshot(doc: userDoc2, data: user2Data),
                ]);
                // It should then cache that value until it is invalidated again.
                expect(identical(snaps, usersObs.get()), true);

                // Deleting a document in the observable's collection should invalidate its cached value.
                userDoc.delete();

                snaps = usersObs.get();
                expect(snaps, [
                  DocumentSnapshot(doc: userDoc2, data: user2Data),
                ]);
                expect(identical(snaps, usersObs.get()), true);

                // Deleting the observable's associated collection should invalidate its cached value.
                usersCollection.delete();
                snaps = usersObs.get();
                expect(snaps, []);
                expect(identical(snaps, usersObs.get()), true);

                userDoc.create(userData);
                snaps = usersObs.get();

                flushBroadcasts(async);

                // After waiting for the broadcast, the observable's cached value should not have changed
                // from its previous recalculation when it was accessed with [get()]. The broadcast should have reused
                // that value.
                expect(identical(snaps, usersObs.get()), true);
              });
            },
          );

          test(
            'Invalidates its cached value when a parent path is deleted',
            () {
              final usersCollection = Loon.collection(
                'users',
                fromJson: TestUserModel.fromJson,
                toJson: (user) => user.toJson(),
              );

              final userDoc = usersCollection.doc('1');
              final userData = TestUserModel('User 1');

              final friendsCollection = userDoc.subcollection(
                'friends',
                fromJson: TestUserModel.fromJson,
                toJson: (user) => user.toJson(),
              );

              final friendDoc = friendsCollection.doc('1');
              final friendData = TestUserModel('Friend 1');

              userDoc.create(userData);
              friendDoc.create(friendData);

              final friendsObs = friendsCollection.observe();

              expect(
                friendsObs.get(),
                [
                  DocumentSnapshot(doc: friendDoc, data: friendData),
                ],
              );

              userDoc.delete();

              expect(
                friendsObs.get(),
                [],
              );
            },
          );

          test(
            'Clears its cached value when it its resources are disposed',
            () {
              final usersCollection = Loon.collection(
                'users',
                fromJson: TestUserModel.fromJson,
                toJson: (user) => user.toJson(),
              );

              final userDoc = usersCollection.doc('1');
              final userData = TestUserModel('User 1');

              userDoc.create(userData);

              final usersObs = usersCollection.observe();

              expect(
                usersObs.get(),
                [
                  DocumentSnapshot(doc: userDoc, data: userData),
                ],
              );

              expect(
                Loon.inspect()['broadcastStore']['observerValues'].isNotEmpty,
                true,
              );

              usersObs.dispose();

              expect(
                Loon.inspect()['broadcastStore']['observerValues'].isEmpty,
                true,
              );
            },
          );
        },
      );

      group(
        'clearAll',
        () {
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
            () {
              fakeAsync((async) {
                final userDoc = TestUserModel.store.doc('1');
                final userData = TestUserModel('User 1');
                final userDocStreamData = <DocumentSnapshot<TestUserModel>?>[];
                final userCollectionStreamData =
                    <List<DocumentSnapshot<TestUserModel>>>[];
                final docSub = userDoc.stream().listen(userDocStreamData.add);
                final collectionSub = TestUserModel.store
                    .stream()
                    .listen(userCollectionStreamData.add);
                flushBroadcasts(async);

                userDoc.create(userData);

                flushBroadcasts(async);

                Loon.clearAll();

                flushBroadcasts(async);

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

                docSub.cancel();
                collectionSub.cancel();
                async.flushMicrotasks();
              });
            },
          );

          test(
            'Does not broadcast the clear to observers when broadcast: false',
            () {
              fakeAsync((async) {
                final userDoc = TestUserModel.store.doc('1');
                final userData = TestUserModel('User 1');

                final docEvents = <DocumentSnapshot<TestUserModel>?>[];
                final collectionEvents =
                    <List<DocumentSnapshot<TestUserModel>>>[];
                final docSub = userDoc.stream().listen(docEvents.add);
                final collectionSub =
                    TestUserModel.store.stream().listen(collectionEvents.add);
                flushBroadcasts(async);

                userDoc.create(userData);
                flushBroadcasts(async);

                Loon.clearAll(broadcast: false);
                flushBroadcasts(async);

                expect(Loon.inspect()['store'], {});
                expect(docEvents, [
                  null,
                  DocumentSnapshot(doc: userDoc, data: userData),
                ]);
                expect(collectionEvents, [
                  [],
                  [DocumentSnapshot(doc: userDoc, data: userData)],
                ]);

                docSub.cancel();
                collectionSub.cancel();
                async.flushMicrotasks();
              });
            },
          );
        },
      );

      group('Root collection', () {
        tearDown(() {
          Loon.clearAll();
        });

        test('Writes documents', () {
          final rootDoc1 = Loon.doc('1');
          final rootSubcollection = rootDoc1.subcollection('friends');
          final rootSubcollectionDoc = rootSubcollection.doc('1');

          expect(rootDoc1.path, 'root__1');
          expect(rootSubcollection.path, 'root__1__friends');
          expect(rootSubcollectionDoc.path, 'root__1__friends__1');

          rootDoc1.create('Test');
          rootSubcollectionDoc.create('Test 2');

          expect(rootDoc1.get(), DocumentSnapshot(doc: rootDoc1, data: 'Test'));
          expect(
            rootSubcollectionDoc.get(),
            DocumentSnapshot(doc: rootSubcollectionDoc, data: 'Test 2'),
          );
        });

        test('Deletes documents', () {
          final data = {"test": true};
          final rootDoc = Loon.doc('1');

          rootDoc.create(data);

          expect(
            Loon.inspect()['store'],
            {
              "root": {
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

      group('Hydrate', () {
        tearDown(() {
          Loon.configure(persistor: null);
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
              seedData: [DocumentSnapshot(doc: userDoc, data: userData)],
            ),
          );

          await Loon.hydrate();

          expect(
            Loon.inspect()['store'],
            {
              "users": {
                "__values": {
                  "1": DocumentSnapshotMatcher(
                    DocumentSnapshot(doc: userDoc, data: userData.toJson()),
                  ),
                }
              }
            },
          );

          // It is then de-serialized when it is first accessed.
          expect(userDoc.get(), DocumentSnapshot(doc: userDoc, data: userData));

          // After the document is read, it is lazily de-serialized.
          expect(
            Loon.inspect()['store'],
            {
              "users": {
                "__values": {
                  "1": DocumentSnapshot(doc: userDoc, data: userData),
                }
              }
            },
          );
        });

        test('Does not overwrite existing documents', () async {
          final userCollection = Loon.collection<TestUserModel>(
            'users',
            fromJson: TestUserModel.fromJson,
            toJson: (user) => user.toJson(),
          );
          final userDoc = userCollection.doc('1');
          final userDoc2 = userCollection.doc('2');

          userDoc.create(TestUserModel('User 1'));

          Loon.configure(
            persistor: TestPersistor(
              seedData: [
                DocumentSnapshot(
                  doc: userDoc,
                  data: TestUserModel('User 1 cached'),
                ),
                DocumentSnapshot(
                  doc: userDoc2,
                  data: TestUserModel('User 2 cached'),
                ),
              ],
            ),
          );

          await Loon.hydrate();

          expect(
            userCollection.get(),
            [
              // User 1 should not have been overwritten by the data hydrated from persistence,
              // since that data is stale and User 1 already exists in memory.
              DocumentSnapshot(
                doc: userDoc,
                data: TestUserModel('User 1'),
              ),
              DocumentSnapshot(
                doc: userDoc2,
                data: TestUserModel('User 2 cached'),
              ),
            ],
          );
        });
      });

      group('Dependencies', () {
        test("Updates the dependencies/dependents stores correctly", () async {
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
          final userDoc = usersCollection.doc('1');
          final userData = {
            "id": 1,
            "name": "User 1",
          };

          postDoc.create(postData);

          expect(
            Loon.inspect()['dependencyStore'],
            {
              "posts": {
                "__values": {
                  "1": {
                    userDoc,
                  }
                }
              }
            },
          );
          expect(
            Loon.inspect()['dependentsStore'],
            {
              userDoc: {
                postDoc,
              },
            },
          );

          // After writing the post, its user doc dependency should exist in the dependency
          // doc cache.
          expect(
            Loon.inspect()['dependencyCache'],
            {
              userDoc,
            },
          );
          userDoc.create(userData);
          userDoc.delete();

          // Deleting the user doc should not alter the post's dependencies, as the post doc remains
          // dependent on the user doc, even when it is no longer in the store, since it could be added back later.
          expect(
            Loon.inspect()['dependencyStore'],
            {
              "posts": {
                "__values": {
                  "1": {
                    userDoc,
                  }
                }
              },
            },
          );
          expect(
            Loon.inspect()['dependentsStore'],
            {
              userDoc: {
                postDoc,
              },
            },
          );

          postDoc.update(postData);

          // Updating the post should not create a duplicate user dependency, it should re-use
          // the existing cached user document.
          expect(
            Loon.inspect()['dependencyCache'],
            {
              userDoc,
            },
          );

          postDoc.update(updatedPostData1);

          // Now the post doc has been updated and is no longer dependent on the user doc.
          expect(
            Loon.inspect()['dependencyStore'],
            {},
          );
          expect(
            Loon.inspect()['dependentsStore'],
            {},
          );

          // Since the user doc no longer has any dependencies, it should be removed from the dependency
          // document cache.
          expect(
            Loon.inspect()['dependencyCache'],
            [],
          );
        });

        test("Rebroadcasts an observable document on dependency changes", () {
          fakeAsync((async) {
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
            final userDoc = usersCollection.doc('1');
            final userData = {"id": 1, "name": "User 1"};
            final updatedUserData = {"id": 1, "name": "User 1 updated"};
            final snaps = <DocumentSnapshot<Json>?>[];
            final sub = postDoc.stream().listen(snaps.add);

            postDoc.create(postData);
            flushBroadcasts(async);
            usersCollection.doc('1').create(userData);
            flushBroadcasts(async);
            userDoc.update(updatedUserData);
            flushBroadcasts(async);
            userDoc.delete();
            flushBroadcasts(async);
            usersCollection.doc('1').create(userData);
            flushBroadcasts(async);
            usersCollection.delete();
            flushBroadcasts(async);
            usersCollection.doc('1').create(userData);
            flushBroadcasts(async);
            postDoc.update(updatedPostData1);
            flushBroadcasts(async);
            // Skips this update to user doc, since the last update to the post
            // caused the user doc to be removed as a dependency.
            userDoc.update(updatedUserData);
            flushBroadcasts(async);
            postDoc.delete();
            flushBroadcasts(async);

            expect(snaps, [
              // No post yet
              null,
              // Post created
              DocumentSnapshot(doc: postDoc, data: postData),
              // Rebroadcast post when user created
              DocumentSnapshot(doc: postDoc, data: postData),
              // Rebroadcast post when user updated
              DocumentSnapshot(doc: postDoc, data: postData),
              // Rebroadcast post when user deleted
              DocumentSnapshot(doc: postDoc, data: postData),
              // Rebroadcast post when user re-added (ensures dependencies remain across deletion/re-creation)
              DocumentSnapshot(doc: postDoc, data: postData),
              // Rebroadcast post when user collection deleted
              DocumentSnapshot(doc: postDoc, data: postData),
              // Rebroadcast post when user re-added
              DocumentSnapshot(doc: postDoc, data: postData),
              // Rebroadcast when post data is updated
              DocumentSnapshot(doc: postDoc, data: updatedPostData1),
              // Rebroadcast when post deleted
              null,
            ]);

            sub.cancel();
            async.flushMicrotasks();
          });
        });

        test(
          "Rebroadcasts an observable query on dependency changes",
          () {
            fakeAsync((async) {
              final usersCollection = Loon.collection<Json>('users');
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
              final userDoc = usersCollection.doc('1');
              final userData = {"id": 1, "name": "User 1"};
              final updatedUserData = {"id": 1, "name": "User 1 updated"};
              final snaps = <List<DocumentSnapshot<Json>>>[];
              final sub = postsCollection.stream().listen(snaps.add);

              postDoc.create(postData);
              flushBroadcasts(async);
              userDoc.create(userData);
              flushBroadcasts(async);
              userDoc.update(updatedUserData);
              flushBroadcasts(async);
              userDoc.delete();
              flushBroadcasts(async);
              userDoc.create(userData);
              flushBroadcasts(async);
              usersCollection.delete();
              flushBroadcasts(async);
              userDoc.create(userData);
              flushBroadcasts(async);
              postDoc.update(updatedPostData1);
              flushBroadcasts(async);
              // Skips this update to user doc, since the last update to the post
              // caused the user doc to be removed as a dependency.
              userDoc.update(updatedUserData);
              flushBroadcasts(async);
              postsCollection.delete();
              flushBroadcasts(async);

              expect(snaps, [
                // No post yet
                [],
                // Post created
                [DocumentSnapshot(doc: postDoc, data: postData)],
                // Rebroadcast posts when user created
                [DocumentSnapshot(doc: postDoc, data: postData)],
                // Rebroadcast posts when user updated
                [DocumentSnapshot(doc: postDoc, data: postData)],
                // Rebroadcast posts when user deleted
                [DocumentSnapshot(doc: postDoc, data: postData)],
                // Rebroadcast posts when user recreated (ensures dependencies remain across deletion/re-creation)
                [DocumentSnapshot(doc: postDoc, data: postData)],
                // Rebroadcast posts when user collection deleted
                [DocumentSnapshot(doc: postDoc, data: postData)],
                // Rebroadcast posts when user recreated
                [DocumentSnapshot(doc: postDoc, data: postData)],
                // Rebroadcast posts when post updated
                [DocumentSnapshot(doc: postDoc, data: updatedPostData1)],
                // Rebroadcast posts when posts collection deleted
                [],
              ]);

              sub.cancel();
              async.flushMicrotasks();
            });
          },
        );

        test("Cyclical dependencies do not cause infinite rebroadcasts", () {
          fakeAsync((async) {
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
            final postsCollection = Loon.collection<Json>(
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
            final userEvents = <DocumentSnapshot<TestUserModel>?>[];
            final sub = userObservable.stream().listen(userEvents.add);

            userDoc.create(userData);

            flushBroadcasts(async);

            expect(
              Loon.inspect()['dependencyStore'],
              {
                "users": {
                  "__values": {
                    "1": {
                      postDoc,
                    },
                  }
                },
              },
            );
            expect(
              Loon.inspect()['dependentsStore'],
              {
                postDoc: {
                  userDoc,
                }
              },
            );

            postDoc.create({
              "id": 1,
              "name": "Post 1",
            });

            expect(
              Loon.inspect()['dependencyStore'],
              {
                "users": {
                  "__values": {
                    "1": {
                      postDoc,
                    },
                  },
                },
                "posts": {
                  "__values": {
                    "1": {
                      userDoc,
                    },
                  },
                },
              },
            );
            expect(
              Loon.inspect()['dependentsStore'],
              {
                postDoc: {
                  userDoc,
                },
                userDoc: {
                  postDoc,
                }
              },
            );

            flushBroadcasts(async);

            userDoc.update(updatedUserData);

            flushBroadcasts(async);

            userObservable.dispose();
            async.flushMicrotasks();

            expect(userEvents, [
              // First emits null when no user has been written.
              null,
              // Emits the initially created user.
              DocumentSnapshot(doc: userDoc, data: userData),
              // Emits the same user again when the post is updated. Infinite rebroadcasting
              // does not occur despite a cyclical dependency between the user and the post since
              // attempts to rebroadcast documents that are already pending broadcast are ignored.
              DocumentSnapshot(doc: userDoc, data: userData),
              // Emits the updated user.
              DocumentSnapshot(doc: userDoc, data: updatedUserData),
            ]);

            sub.cancel();
            async.flushMicrotasks();
          });
        });

        test("Deleting a collection clears its dependencies", () {
          fakeAsync((async) {
            final usersCollection = Loon.collection(
              'users',
              fromJson: TestUserModel.fromJson,
              toJson: (snap) => snap.toJson(),
            );
            final friendsCollection = Loon.collection(
              'friends',
              fromJson: TestUserModel.fromJson,
              toJson: (snap) => snap.toJson(),
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

            flushBroadcasts(async);

            expect(Loon.inspect()['dependencyStore'], {
              "friends": {
                "__values": {
                  "1": {
                    userDoc,
                  }
                }
              }
            });
            expect(
              Loon.inspect()['dependentsStore'],
              {
                userDoc: {
                  friendDoc,
                }
              },
            );

            friendsCollection.delete();

            flushBroadcasts(async);

            expect(
              Loon.inspect()['dependencyStore'],
              {},
            );
            expect(
              Loon.inspect()['dependentsStore'],
              {
                // The dependents are not cleared when a collection is cleared, instead
                // the dependents are lazily cleared when the dependent is updated.
                userDoc: {
                  friendDoc,
                },
              },
            );

            // Now that the user has been updated, it has cleared its friend dependent.
            userDoc.update(TestUserModel('User 1 updated'));

            flushBroadcasts(async);

            expect(Loon.inspect()['dependencyStore'], {});
            expect(Loon.inspect()['dependentsStore'], {});
          });
        });
      });

      group(
        'Transaction',
        () {
          test(
            'Writes all documents',
            () async {
              final userDoc = TestUserModel.store.doc('1');
              final userDoc2 = TestUserModel.store.doc('2');
              final userData = TestUserModel('User 1');
              final userDataUpdated = TestUserModel('User 1 updated');
              final userData2 = TestUserModel('User 2');

              await Loon.transaction((writer) async {
                writer.create(userDoc, userData);
                writer.create(userDoc2, userData2);
                writer.update(userDoc, userDataUpdated);
              });

              expect(
                userDoc.get(),
                DocumentSnapshot(doc: userDoc, data: userDataUpdated),
              );
              expect(
                userDoc2.get(),
                DocumentSnapshot(doc: userDoc2, data: userData2),
              );
            },
          );

          test(
            'Automatically rolls back changes if the transaction fails',
            () async {
              final userDoc = TestUserModel.store.doc('1');
              final userDoc2 = TestUserModel.store.doc('2');
              final userData = TestUserModel('User 1');
              final userDataUpdated = TestUserModel('User 1 updated');
              final userData2 = TestUserModel('User 2');

              userDoc.create(userData);
              userDoc2.create(userData2);

              try {
                await Loon.transaction((writer) async {
                  writer.update(userDoc, userDataUpdated);
                  writer.delete(userDoc2);

                  // Trying to recreate the existing user document throws an error.
                  writer.create(userDoc, userDataUpdated);
                });
              } catch (e) {
                expect(
                  userDoc.get(),
                  DocumentSnapshot(doc: userDoc, data: userData),
                );
                expect(
                  userDoc2.get(),
                  DocumentSnapshot(doc: userDoc2, data: userData2),
                );
              }
            },
          );

          test(
            'Rolls back to non-existence when a previously-missing document is '
            'written more than once in the transaction',
            () async {
              final userDoc = TestUserModel.store.doc('1');
              final userData = TestUserModel('User 1');
              final userDataUpdated = TestUserModel('User 1 updated');

              expect(userDoc.exists(), false);

              try {
                await Loon.transaction((writer) async {
                  writer.create(userDoc, userData);
                  writer.update(userDoc, userDataUpdated);
                  throw 'fail';
                });
              } catch (_) {}

              expect(userDoc.exists(), false);
              expect(userDoc.get(), null);
            },
          );
        },
      );
    },
  );
}
