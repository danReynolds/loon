import 'package:loon/loon.dart';
import '../utils.dart';
import 'test_user_model.dart';

/// A dummy persistor used in the test environment that doesn't actually engage with any persistence storage
/// mechanism (file system, etc) and is just used to test the base [Persistor] batching and de-duping.
class TestPersistor extends Persistor {
  static final completer = PersistorCompleter();

  final List<DocumentSnapshot<TestUserModel>> seedData;

  TestPersistor({
    void Function(Set<Document> batch)? onPersist,
    void Function(Set<Collection> collections)? onClear,
    void Function()? onClearAll,
    void Function(HydrationData data)? onHydrate,
    required this.seedData,
  }) : super(
          settings: const PersistorSettings(),
          onPersist: (docs) {
            completer.persistComplete();
            onPersist?.call(docs);
          },
          onClear: (collections) {
            completer.clearComplete();
            onClear?.call(collections);
          },
          onClearAll: () {
            completer.clearAllComplete();
            onClearAll?.call();
          },
          onHydrate: (data) {
            completer.hydrateComplete();
            onHydrate?.call(data);
          },
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
