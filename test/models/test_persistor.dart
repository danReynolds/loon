import 'dart:async';

import 'package:loon/loon.dart';
import 'test_user_model.dart';

/// A dummy persistor used in the test environment that doesn't actually engage with any persistence storage
/// mechanism (file system, etc) and is just used to test the base [Persistor] batching and de-duping.
class TestPersistor extends Persistor {
  final List<DocumentSnapshot<TestUserModel>> seedData;

  TestPersistor({
    super.persistenceThrottle,
    super.onPersist,
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
  persist(docs) async {}

  @override
  clear() async {}

  @override
  init() async {}
}
