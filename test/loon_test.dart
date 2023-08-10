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

  toJson() {
    return {
      "name": name,
    };
  }
}

class DocumentSnapshotMatcher extends Matcher {
  DocumentSnapshot<TestUserModel> expected;
  late DocumentSnapshot<TestUserModel> actual;
  DocumentSnapshotMatcher(this.expected);

  @override
  Description describe(Description description) {
    return description.add(
      "has expected document ID: ${expected.id}, data: ${expected.data}",
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
    final actual0 = actual as DocumentSnapshot<TestUserModel>;
    this.actual = actual0;
    return actual.id == expected.id &&
        mapsEqual(
          actual.data.toJson(),
          expected.data.toJson(),
        );
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

    test('Instance document added without serializer throws error', () {
      expect(
        () => Loon.collection('users').doc('1').create(TestUserModel('1')),
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

    test('Instance document updated without serializer throws error', () {
      expect(
        () => Loon.collection('users').doc('1').update(TestUserModel('1')),
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

    test('Instance document modified without serializer throws error', () {
      expect(
        () => Loon.collection('users')
            .doc('1')
            .modify((userSnap) => TestUserModel('1')),
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
      Loon.clearAll();
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

    test('Defaults to non-multicast observables', () {
      final userDoc = TestUserModel.store.doc('1');
      final userDocObservable = userDoc.observe();
      userDocObservable.stream().listen(null);

      expect(
        // A second subscription to the non-multicast observable should throw.
        () => userDocObservable.stream().listen(null),
        throwsStateError,
      );
    });

    test('Automatically disposes non-multicast observables', () {
      final userDoc = TestUserModel.store.doc('1');
      final userDocObservable = userDoc.observe();
      final subscription = userDocObservable.stream().listen(null);
      subscription.cancel();
      expect(userDocObservable.isClosed, true);
    });

    test('Requires manual disposal of multi cast observables', () {
      final userDoc = TestUserModel.store.doc('1');
      final userDocObservable = userDoc.observe(multicast: true);
      final subscription = userDocObservable.stream().listen(null);
      final subscription2 = userDocObservable.stream().listen(null);
      subscription.cancel();
      subscription2.cancel();

      expect(userDocObservable.isClosed, false);
      userDocObservable.dispose();
      expect(userDocObservable.isClosed, true);
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

  group('Computables', () {
    tearDown(() {
      Loon.clearAll();
    });

    test('Execute computations correctly', () {
      final user = TestUserModel('User 1');
      final user2 = TestUserModel('User 2');
      final userDoc = TestUserModel.store.doc('1');
      final userDoc2 = TestUserModel.store.doc('2');

      userDoc.create(user);
      userDoc2.create(user2);

      final namesComputation = Loon.compute2<List<String>,
          DocumentSnapshot<TestUserModel>?, DocumentSnapshot<TestUserModel>?>(
        userDoc,
        userDoc2,
        (userSnap, userSnap2) {
          return [userSnap, userSnap2]
              .whereType<DocumentSnapshot<TestUserModel>>()
              .map((snap) => snap.data.name)
              .toList();
        },
      );

      expect(namesComputation.get(), ['User 1', 'User 2']);
    });

    test('Execute recomputations correctly', () {
      final user = TestUserModel('User 1');
      final user2 = TestUserModel('User 2');
      final userDoc = TestUserModel.store.doc('1');
      final userDoc2 = TestUserModel.store.doc('2');

      userDoc.create(user);
      userDoc2.create(user2);

      final namesComputation = Loon.compute2<List<String>,
          DocumentSnapshot<TestUserModel>?, DocumentSnapshot<TestUserModel>?>(
        userDoc,
        userDoc2,
        (userSnap, userSnap2) {
          return [userSnap, userSnap2]
              .whereType<DocumentSnapshot<TestUserModel>>()
              .map((snap) => snap.data.name)
              .toList();
        },
      );

      expect(namesComputation.get(), ['User 1', 'User 2']);
      userDoc.update(TestUserModel('Updated User 1'));
      expect(namesComputation.get(), ['Updated User 1', 'User 2']);
    });

    test('Execute stream recomputations correctly', () async {
      final user = TestUserModel('User 1');
      final user2 = TestUserModel('User 2');
      final userDoc = TestUserModel.store.doc('1');
      final userDoc2 = TestUserModel.store.doc('2');

      final namesComputation = Loon.compute2<List<String>,
          DocumentSnapshot<TestUserModel>?, DocumentSnapshot<TestUserModel>?>(
        userDoc,
        userDoc2,
        (userSnap, userSnap2) {
          return [userSnap, userSnap2]
              .whereType<DocumentSnapshot<TestUserModel>>()
              .map((snap) => snap.data.name)
              .toList();
        },
      );

      final namesObs = namesComputation.observe();
      final namesStream = namesObs.stream();

      await asyncEvent();

      userDoc.create(user);
      userDoc2.create(user2);

      await asyncEvent();

      userDoc.update(TestUserModel('Updated User 1'));

      await asyncEvent();

      namesObs.dispose();

      expectLater(
        namesStream,
        emitsInOrder([
          [],
          ['User 1', 'User 2'],
          ['Updated User 1', 'User 2'],
          emitsDone,
        ]),
      );
    });

    test('supports query computables', () {
      final user = TestUserModel('User 1');
      final user2 = TestUserModel('User 2');
      final userDoc = TestUserModel.store.doc('1');
      final userDoc2 = TestUserModel.store.doc('2');

      userDoc.create(user);
      userDoc2.create(user2);

      final userQuery = TestUserModel.store;

      final matchUserComputation = Loon.compute2<
          DocumentSnapshot<TestUserModel>?,
          DocumentSnapshot<TestUserModel>?,
          List<DocumentSnapshot<TestUserModel>>>(
        userDoc,
        userQuery,
        (userSnap, usersSnap) {
          return usersSnap
              .firstWhere((snap) => snap.doc.id == userSnap?.doc.id);
        },
      );

      expect(matchUserComputation.get()?.data.toJson(), user.toJson());
    });

    test('supports composing computations', () {
      final user = TestUserModel('User 1');
      final user2 = TestUserModel('User 2');
      final userDoc = TestUserModel.store.doc('1');
      final userDoc2 = TestUserModel.store.doc('2');

      userDoc.create(user);
      userDoc2.create(user2);

      final namesComputation = Loon.compute2<List<String>,
          DocumentSnapshot<TestUserModel>?, DocumentSnapshot<TestUserModel>?>(
        userDoc,
        userDoc2,
        (userSnap, userSnap2) {
          return [userSnap, userSnap2]
              .whereType<DocumentSnapshot<TestUserModel>>()
              .map((snap) => snap.data.name)
              .toList();
        },
      );

      final matchingNameComputation = Loon.compute2<String?,
          DocumentSnapshot<TestUserModel>?, List<String>>(
        userDoc,
        namesComputation,
        (userSnap, userNames) {
          return userNames.firstWhere((name) => name == userSnap?.data.name);
        },
      );

      expect(matchingNameComputation.get(), 'User 1');
    });

    test('map computes correctly', () {
      final user = TestUserModel('User 1');
      final user2 = TestUserModel('User 2');
      final userDoc = TestUserModel.store.doc('1');
      final userDoc2 = TestUserModel.store.doc('2');

      userDoc.create(user);
      userDoc2.create(user2);

      final namesComputation = Loon.compute2<List<String>,
          DocumentSnapshot<TestUserModel>?, DocumentSnapshot<TestUserModel>?>(
        userDoc,
        userDoc2,
        (userSnap, userSnap2) {
          return [userSnap, userSnap2]
              .whereType<DocumentSnapshot<TestUserModel>>()
              .map((snap) => snap.data.name)
              .toList();
        },
      );

      final joinedNamesComputation =
          namesComputation.map<String>((names) => names.join(', '));

      expect(joinedNamesComputation.get(), 'User 1, User 2');
    });

    test('switchMap supports mapping computations', () async {
      final user = TestUserModel('User 1');
      final user2 = TestUserModel('User 2');
      final user3 = TestUserModel('User 3');
      final userDoc = TestUserModel.store.doc('1');
      final userDoc2 = TestUserModel.store.doc('2');
      final userDoc3 = TestUserModel.store.doc('3');

      userDoc.create(user);
      userDoc2.create(user2);
      userDoc3.create(user3);

      await asyncEvent();

      final namesComputation = Loon.compute2<List<String>,
          DocumentSnapshot<TestUserModel>?, DocumentSnapshot<TestUserModel>?>(
        userDoc,
        userDoc2,
        (userSnap, userSnap2) {
          return [userSnap, userSnap2]
              .whereType<DocumentSnapshot<TestUserModel>>()
              .map((snap) => snap.data.name)
              .toList();
        },
      );

      final mappedComputation =
          namesComputation.switchMap<List<String>>((names) {
        return Loon.compute2<List<String>, DocumentSnapshot<TestUserModel>?,
            DocumentSnapshot<TestUserModel>?>(
          userDoc2,
          userDoc3,
          (userSnap2, userSnap3) {
            return [userSnap2, userSnap3]
                .whereType<DocumentSnapshot<TestUserModel>>()
                .map((snap) => snap.data.name)
                .toList();
          },
        );
      });

      final observableMappedComputation = mappedComputation.observe();

      await asyncEvent();

      userDoc.update(TestUserModel('User 1 Updated'));

      await asyncEvent();

      userDoc3.update(TestUserModel('User 3 Updated'));

      await asyncEvent();

      observableMappedComputation.dispose();

      await expectLater(
        observableMappedComputation.stream(),
        emitsInOrder([
          [
            'User 2',
            'User 3',
          ],
          [
            'User 2',
            'User 3',
          ],
          [
            'User 2',
            'User 3 Updated',
          ],
          emitsDone,
        ]),
      );
    });

    test('switchMap supports mapping to queries', () async {
      final user = TestUserModel('User 1');
      final user2 = TestUserModel('User 2');
      final user3 = TestUserModel('User 2');
      final userDoc = TestUserModel.store.doc('1');
      final userDoc2 = TestUserModel.store.doc('2');
      final userDoc3 = TestUserModel.store.doc('3');

      userDoc.create(user);
      userDoc2.create(user2);
      userDoc3.create(user3);

      await asyncEvent();

      final userIdsComputation = Loon.compute2<List<String>,
          DocumentSnapshot<TestUserModel>?, DocumentSnapshot<TestUserModel>?>(
        userDoc,
        userDoc2,
        (userSnap, userSnap2) {
          return [userSnap, userSnap2]
              .whereType<DocumentSnapshot<TestUserModel>>()
              .map((snap) => snap.id)
              .toList();
        },
      );

      final otherUserIdsComputation = userIdsComputation.switchMap((ids) {
        return TestUserModel.store.where((snap) {
          return !ids.contains(snap.id);
        }).map((snaps) => snaps.map((snap) => snap.id).toList());
      });

      final observableOtherUserIdsComputation =
          otherUserIdsComputation.observe();

      await asyncEvent();

      userDoc.update(TestUserModel('User 1 Updated'));

      await asyncEvent();

      userDoc3.delete();

      await asyncEvent();

      observableOtherUserIdsComputation.dispose();

      await expectLater(
        observableOtherUserIdsComputation.stream(),
        emitsInOrder([
          ['3'],
          ['3'],
          [],
          emitsDone,
        ]),
      );
    });

    test('switchMap supports mapping to documents', () async {
      final user = TestUserModel('User 1');
      final user2 = TestUserModel('User 2');
      final userDoc = TestUserModel.store.doc('1');
      final userDoc2 = TestUserModel.store.doc('2');

      userDoc.create(user);
      userDoc2.create(user2);

      await asyncEvent();

      final mappedUserComputable = userDoc.switchMap((userSnap) {
        return userDoc2;
      }).map((snap) => snap!.data.name);

      final observableMappedUserComputable = mappedUserComputable.observe();

      await asyncEvent();

      userDoc.update(TestUserModel('User 1 Updated'));

      await asyncEvent();

      userDoc2.update(TestUserModel('User 2 Updated'));

      await asyncEvent();

      observableMappedUserComputable.dispose();

      await expectLater(
        observableMappedUserComputable.stream(),
        emitsInOrder([
          'User 2',
          'User 2',
          'User 2 Updated',
          emitsDone,
        ]),
      );
    });

    test('switchMap supports mapping to computable values', () async {
      final user = TestUserModel('User 1');
      final userDoc = TestUserModel.store.doc('1');

      userDoc.create(user);

      await asyncEvent();

      final mappedUserComputable =
          userDoc.switchMap((_) => Computable.value('Test'));

      final observableMappedUserComputable = mappedUserComputable.observe();

      await asyncEvent();

      userDoc.update(TestUserModel('User 1 Updated'));

      await asyncEvent();

      userDoc.update(TestUserModel('User 1 Updated Again'));

      await asyncEvent();

      observableMappedUserComputable.dispose();

      await expectLater(
        observableMappedUserComputable.stream(),
        emitsInOrder([
          'Test',
          'Test',
          'Test',
          emitsDone,
        ]),
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
}
