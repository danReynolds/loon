import 'package:flutter/foundation.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:loon/loon.dart';

Future<void> asyncEvent() {
  return Future.delayed(const Duration(milliseconds: 1), () => null);
}

bool mapsEqual(Map<dynamic, dynamic> map1, Map<dynamic, dynamic> map2) {
  if (map1.length != map2.length) return false;

  for (var key in map1.keys) {
    if (!map2.containsKey(key) || map1[key] != map2[key]) {
      return false;
    }
  }

  return true;
}

class TestUserModel {
  final String name;

  TestUserModel(this.name);

  static Collection<TestUserModel> get store {
    return Loon.collection<TestUserModel>(
      'users',
      fromJson: TestUserModel.fromJson,
      toJson: (user) => user.toJson(),
    );
  }

  TestUserModel.fromJson(Json json) : name = json['name'];

  Json toJson() {
    return {
      "name": name,
    };
  }

  @override
  bool operator ==(Object other) {
    if (identical(this, other)) {
      return true;
    }
    if (other is TestUserModel) {
      return name == other.name;
    }
    return false;
  }

  @override
  int get hashCode => Object.hashAll([name]);
}

class TestPersistor extends Persistor {
  final List<DocumentSnapshot<TestUserModel>> seedData;

  TestPersistor({
    required this.seedData,
  });

  @override
  Future<SerializedCollectionStore> hydrate() async {
    return {
      "users": seedData.fold({}, (acc, doc) {
        return {
          ...acc,
          doc.id: doc.data.toJson(),
        };
      }),
    };
  }

  @override
  Future<void> persist(List<BroadcastDocument> docs) {
    throw UnimplementedError();
  }
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
      "has expected document ID: ${matchState['actual'].id}, data: ${matchState['actual'].data}",
    );
  }

  @override
  bool matches(actual, Map matchState) {
    final actual0 = actual as DocumentSnapshot<T>?;
    this.actual = actual0;

    final actualData = actual?.data;
    final expectedData = expected?.data;

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

    test('Instance user document created successfully', () {
      final user = TestUserModel('User 1');
      final userDoc = TestUserModel.store.doc('1');

      userDoc.create(user);

      expect(
        userDoc.getJson(),
        user.toJson(),
      );
    });

    test('JSON user document created successfully', () {
      final userCollection = Loon.collection('users');
      final userDoc = userCollection.doc('2');
      final userJson = {
        "name": "User 2",
      };

      userDoc.create(userJson);

      expect(
        userDoc.getJson(),
        userJson,
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
      final userSnap = userDoc.get();

      expect(
        userSnap?.id,
        '1',
      );

      expect(
        userSnap?.data.toJson(),
        user.toJson(),
      );
    });

    test('JSON user document read successfully', () {
      final userCollection = Loon.collection('users');
      final userDoc = userCollection.doc('2');
      final userJson = {
        "name": "User 2",
      };

      userDoc.create(userJson);
      final userSnap = userDoc.get();

      expect(
        userSnap?.id,
        '2',
      );

      expect(
        userSnap?.data,
        userJson,
      );
    });
  });

  group('Update document', () {
    tearDown(() {
      Loon.clearAll();
    });

    test('Existing instance user document updated successfully', () {
      final updatedUser = TestUserModel('User 1 updated');
      final userDoc = TestUserModel.store.doc('1');

      userDoc.create(TestUserModel('User 1'));
      userDoc.update(updatedUser);
      final userSnap = userDoc.get();

      expect(
        userSnap?.id,
        '1',
      );

      expect(
        userSnap?.data.toJson(),
        updatedUser.toJson(),
      );
    });

    test('New instance user document updated successfully', () {
      final updatedUser = TestUserModel('User 1');
      final userDoc = TestUserModel.store.doc('1');

      userDoc.update(updatedUser);
      final userSnap = userDoc.get();

      expect(
        userSnap?.id,
        '1',
      );

      expect(
        userSnap?.data.toJson(),
        updatedUser.toJson(),
      );
    });

    test('JSON user document updated successfully', () {
      final userCollection = Loon.collection('users');
      final userDoc = userCollection.doc('2');
      final userJson = {
        "name": "User 2",
      };

      userDoc.create(userJson);

      expect(
        userDoc.getJson(),
        userJson,
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

    test('Existing instance user document modified successfully', () {
      final updatedUser = TestUserModel('User 1 updated');
      final userDoc = TestUserModel.store.doc('1');

      userDoc.create(TestUserModel('User 1'));
      userDoc.modify((userSnap) => updatedUser);
      final userSnap = userDoc.get();

      expect(
        userSnap?.id,
        '1',
      );

      expect(
        userSnap?.data.toJson(),
        updatedUser.toJson(),
      );
    });

    test('New instance user document modified successfully', () {
      final updatedUser = TestUserModel('User 1');
      final userDoc = TestUserModel.store.doc('1');

      userDoc.modify((userSnap) => updatedUser);
      final userSnap = userDoc.get();

      expect(
        userSnap?.id,
        '1',
      );

      expect(
        userSnap?.data.toJson(),
        updatedUser.toJson(),
      );
    });

    test('JSON user document modified successfully', () {
      final userCollection = Loon.collection('users');
      final userDoc = userCollection.doc('2');
      final userJson = {
        "name": "User 2",
      };

      userDoc.modify((userSnap) => userJson);

      expect(
        userDoc.getJson(),
        userJson,
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

      expect(
        snaps[0].type,
        BroadcastEventTypes.added,
      );
      expect(
        snaps[0].prevData,
        null,
      );
      expect(
        snaps[0].data,
        user,
      );

      expect(
        snaps[1].type,
        BroadcastEventTypes.modified,
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

      final queryStream = TestUserModel.store
          .where((snap) {
            return snap.data.name == 'User 1';
          })
          .stream()
          // We take 3 changes instead of 2 here because the stream first immediately emits its current value,
          // and then the broadcast scheduled by the create call re-executes the query and emits the updated value. We don't
          // care about this intermediary broadcast and just compare the first/last result.
          .take(3);

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
        BroadcastEventTypes.added,
      );
      expect(
        snaps[0].first.data,
        user,
      );

      expect(
        snaps[0].last.type,
        BroadcastEventTypes.added,
      );
      expect(
        snaps[0].last.data,
        user2,
      );

      expect(snaps[1].length, 1);

      expect(
        snaps[1].first.type,
        BroadcastEventTypes.modified,
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
        // The global event is a [BroadcastEventTypes.modified] when the user is updated,
        // but to this query, it should be a [BroadcastEventTypes.added] event since previously
        // it was not included and now it is.
        BroadcastEventTypes.added,
      );
    });
  });

  group('Clear collection', () {
    tearDown(() {
      Loon.clearAll();
    });

    test('Clears all documents in the collection', () {
      final userDoc = TestUserModel.store.doc('1');
      final userDoc2 = TestUserModel.store.doc('2');

      userDoc.create(TestUserModel('User 1'));
      userDoc2.create(TestUserModel('User 2'));

      TestUserModel.store.clear();

      expect(userDoc.get(), null);
      expect(userDoc2.get(), null);
    });
  });

  group('Replace collection', () {
    tearDown(() {
      Loon.clearAll();
    });

    test('Replaces all documents in the collection', () {
      final userDoc = TestUserModel.store.doc('1');
      final userDoc2 = TestUserModel.store.doc('2');

      userDoc.create(TestUserModel('User 1'));
      userDoc2.create(TestUserModel('User 2'));

      TestUserModel.store.replace([
        DocumentSnapshot(doc: userDoc, data: TestUserModel('User 3')),
      ]);

      expect(userDoc.get()?.data.toJson(), TestUserModel('User 3').toJson());
      expect(userDoc2.get(), null);
    });
  });

  group('Clearing all collections', () {
    tearDown(() {
      Loon.clearAll();
    });

    test('Clears all documents across all collections', () {
      final userDoc = TestUserModel.store.doc('1');
      final userDoc2 = Loon.collection<TestUserModel>(
        'users2',
        fromJson: TestUserModel.fromJson,
        toJson: (user) => user.toJson(),
      ).doc('2');

      userDoc.create(TestUserModel('User 1'));
      userDoc2.create(TestUserModel('User 2'));

      Loon.clearAll();

      expect(userDoc.get(), null);
      expect(userDoc2.get(), null);
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

      final rootSnap = rootDoc.get();

      expect(rootSnap?.collection, '__ROOT__');
      expect(rootSnap?.id, '1');
      expect(rootSnap?.data, data);
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
            toJson: (friend) => friend.toJson(),
          )
          .doc('1');

      friendDoc.create(friendData);
      final friendSnap = friendDoc.get();

      expect(friendSnap?.data.toJson(), friendData.toJson());
      expect(friendSnap?.doc.collection, 'users_1_friends');
      expect(friendSnap?.doc.id, '1');
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
      final userDoc = userCollection.doc('User 1');
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

      expect(
        userDoc.get()?.data,
        userData,
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

      await asyncEvent();

      usersCollection.doc('1').create({
        "id": 1,
        "name": "User 1",
      });

      await asyncEvent();

      postDoc.update(updatedPostData1);

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
      final userData = TestUserModel('Test user 1');
      final updatedUserData = TestUserModel('Test user 1 updated');
      final userObservable = userDoc.observe();
      final userStream = userObservable.stream();

      userDoc.create(userData);

      await asyncEvent();

      postsCollection.doc('1').create({
        "id": 1,
        "name": "Post 1",
      });

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
  });
}
