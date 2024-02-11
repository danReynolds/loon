import 'package:flutter_test/flutter_test.dart';
import 'package:loon/loon.dart';

import 'models/test_persistor.dart';
import 'models/test_user_model.dart';

void main() {
  tearDown(() {
    Loon.clearAll();
  });

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

      await Future.delayed(const Duration(milliseconds: 2));

      userCollection.doc('3').create(TestUserModel('User 3'));

      await Future.delayed(const Duration(milliseconds: 2));

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
}
