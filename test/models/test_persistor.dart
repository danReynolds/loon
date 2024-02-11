import 'package:loon/loon.dart';
import 'test_user_model.dart';

class TestPersistor extends Persistor {
  final List<DocumentSnapshot<TestUserModel>> seedData;

  TestPersistor({
    super.persistenceThrottle,
    required this.seedData,
    super.onPersist,
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
  persist(docs) async {
    onPersist?.call(docs);
  }

  @override
  clear(collection) async {}

  @override
  clearAll() async {}

  @override
  init() async {}
}
