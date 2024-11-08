import 'package:flutter_test/flutter_test.dart';
import 'package:loon/loon.dart';

import '../../models/test_persistor.dart';
import '../../models/test_user_model.dart';

void main() {
  tearDown(() {
    Loon.clearAll();
  });

  group('Persistor', () {
    test(
      'Batches contiguous persistence operations',
      () async {
        List<Set<Document>> batches = [];

        Loon.configure(
          persistor: TestPersistor(
            seedData: [],
            onPersist: (docs) {
              batches.add(docs);
            },
          ),
        );

        final userCollection = Loon.collection(
          'users',
          fromJson: TestUserModel.fromJson,
          toJson: (user) => user.toJson(),
        );

        userCollection.doc('1').create(TestUserModel('User 1'));
        userCollection.doc('2').create(TestUserModel('User 2'));

        await TestPersistor.completer.onPersist;

        userCollection.doc('3').create(TestUserModel('User 3'));

        await TestPersistor.completer.onPersist;

        // There should be two persistence calls:
        // 1. The first two writes should be grouped together into a single batch in the first 1ms throttle.
        // 2. The third write is grouped into its own batch.
        expect(batches.length, 2);
        expect(
          batches.first,
          {
            userCollection.doc('1'),
            userCollection.doc('2'),
          },
        );
        expect(batches.last, {userCollection.doc('3')});
      },
    );

    test(
      'Does not batch non-contiguous operations',
      () async {
        List<Set<Document>> batches = [];

        Loon.configure(
          persistor: TestPersistor(
            seedData: [],
            onPersist: (docs) {
              batches.add(docs);
            },
          ),
        );

        final userCollection = Loon.collection(
          'users',
          fromJson: TestUserModel.fromJson,
          toJson: (user) => user.toJson(),
        );

        userCollection.doc('1').create(TestUserModel('User 1'));
        userCollection.delete();
        userCollection.doc('2').create(TestUserModel('User 2'));

        await TestPersistor.completer.onPersist;
        await TestPersistor.completer.onClear;
        await TestPersistor.completer.onPersist;

        // There should be a separate persistence call for each document in this scenario since the operation
        // order must be persist->clear->persist in order to ensure the correct sequencing of events.
        expect(batches.length, 2);
        expect(
          batches.first,
          {userCollection.doc('1')},
        );
        expect(batches.last, {userCollection.doc('2')});
      },
    );

    test(
      'De-dupes persisting the same document',
      () async {
        List<Set<Document>> batches = [];

        Loon.configure(
          persistor: TestPersistor(
            seedData: [],
            onPersist: (docs) {
              batches.add(docs);
            },
          ),
        );

        final userCollection = Loon.collection(
          'users',
          fromJson: TestUserModel.fromJson,
          toJson: (user) => user.toJson(),
        );

        userCollection.doc('1').create(TestUserModel('User 1'));
        userCollection.doc('1').update(TestUserModel('User 1 updated'));

        await TestPersistor.completer.onPersist;

        userCollection.doc('2').create(TestUserModel('User 2'));

        await TestPersistor.completer.onPersist;

        expect(batches.length, 2);

        // The multiple updates to user doc 1 are grouped and de-duped in the same batch. Persistors can read the current
        // value of the documents in the batch so there is no need to include document updates again.
        expect(batches.first, [userCollection.doc('1')]);
        expect(batches.last, [userCollection.doc('2')]);
      },
    );

    test(
      'Batches clearing of collections',
      () async {
        List<Set<Collection>> batches = [];

        Loon.configure(
          persistor: TestPersistor(
            seedData: [],
            onClear: (collections) {
              batches.add(collections);
            },
          ),
        );

        Loon.collection('users').delete();
        Loon.collection('posts').delete();

        await TestPersistor.completer.onClear;

        Loon.collection('messages').delete();

        await TestPersistor.completer.onClear;

        expect(batches.length, 2);

        expect(batches.first,
            [Loon.collection('users'), Loon.collection('posts')]);
        expect(batches.last, [Loon.collection('messages')]);
      },
    );
  });
}
