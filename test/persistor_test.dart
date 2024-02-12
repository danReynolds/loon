import 'package:flutter_test/flutter_test.dart';
import 'package:loon/loon.dart';

import 'models/test_persistor.dart';
import 'models/test_user_model.dart';
import 'utils.dart';

void main() {
  final completer = PersistorCompleter();

  tearDown(() {
    Loon.clear();
  });

  group('Persistor', () {
    test(
      'Persistence batches using the throttle',
      () async {
        List<List<Document>> batches = [];

        Loon.configure(
          persistor: TestPersistor(
            seedData: [],
            persistenceThrottle: const Duration(milliseconds: 1),
            onPersist: (docs) {
              batches.add(docs);
              completer.persistComplete();
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

        await completer.onPersistComplete;

        userCollection.doc('3').create(TestUserModel('User 3'));

        await completer.onPersistComplete;

        // There should be two calls to the persistor:
        // 1. The first two writes should be grouped together into a single batch in the first 1ms throttle.
        // 2. The third write is grouped into its own batch.
        expect(batches.length, 2);
        expect(
          batches.first,
          [
            userCollection.doc('1'),
            userCollection.doc('2'),
          ],
        );
        expect(batches.last, [userCollection.doc('3')]);
      },
    );

    test(
      'De-dupes persisting documents',
      () async {
        List<List<Document>> batches = [];

        Loon.configure(
          persistor: TestPersistor(
            seedData: [],
            persistenceThrottle: const Duration(milliseconds: 1),
            onPersist: (docs) {
              batches.add(docs);
              completer.persistComplete();
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

        await completer.onPersistComplete;

        userCollection.doc('2').create(TestUserModel('User 2'));

        await completer.onPersistComplete;

        expect(batches.length, 2);

        // The multiple updates to user doc 1 are grouped and de-duped in the same batch. Persistors can read the current
        // value of the documents in the batch so there is no need to include document updates again.
        expect(batches.first, [userCollection.doc('1')]);
        expect(batches.last, [userCollection.doc('2')]);
      },
    );
  });
}
