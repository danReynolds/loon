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
          settings: const PersistorSettings(
            persistenceThrottle: Duration(milliseconds: 1),
          ),
        );

  @override
  hydrate([collections]) async {
    return seedData.fold<HydrationData>({}, (acc, doc) {
      return {
        ...acc,
        doc.id: doc.data.toJson(),
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
