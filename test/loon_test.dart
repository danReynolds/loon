import 'package:flutter_test/flutter_test.dart';
import 'package:loon/loon.dart';

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

void main() {
  group('Create document', () {
    tearDown(() {
      Loon.clearAll();
    });

    test('Instance user document added successfully', () {
      final user = TestUserModel('User 1');
      final userDoc = TestUserModel.store.doc('1');

      userDoc.create(user);

      expect(
        userDoc.getJson(),
        user.toJson(),
      );
    });

    test('JSON user document added successfully', () {
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

    test('Instance document read without serializer throws error', () {
      final user = TestUserModel('User 1');
      final userDoc = TestUserModel.store.doc('1');

      userDoc.create(user);

      expect(
        () => Loon.collection<TestUserModel>('users').doc('1').get(),
        throwsException,
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
}
