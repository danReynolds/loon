import 'package:loon/loon.dart';
import 'test_user_model.dart';

/// A dummy persistor used in the test environment that doesn't actually engage with any persistence storage
/// mechanism (file system, etc) and is just used to test the base [Persistor] batching and de-duping.
class TestPersistor extends Persistor {
  final List<DocumentSnapshot<TestUserModel>> seedData;

  TestPersistor({
    super.onPersist,
    required this.seedData,
  }) : super(
          persistenceThrottle: const Duration(milliseconds: 1),
          settings: const PersistorSettings(),
        );

  @override
  hydrate([collections]) async {
    return seedData.fold<HydrationData>({}, (acc, doc) {
      return {
        ...acc,
        doc.path: doc.data.toJson(),
      };
    });
  }

  @override
  persist(docs) async {}

  @override
  clear(collection) async {}

  @override
  clearAll() async {}

  @override
  init() async {}
}
