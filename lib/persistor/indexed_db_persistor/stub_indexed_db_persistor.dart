import 'package:loon/loon.dart';

class IndexedDBPersistor extends Persistor {
  IndexedDBPersistor({
    super.onClear,
    super.onClearAll,
    super.onHydrate,
    super.onPersist,
    super.onSync,
    super.persistenceThrottle,
    super.settings,
  }) : super(logger: Logger('IndexedDBStubPersistor'));

  @override
  Future<void> clear(List<Collection> collections) {
    throw UnimplementedError();
  }

  @override
  Future<void> clearAll() {
    throw UnimplementedError();
  }

  @override
  Future<Json> hydrate([List<StoreReference>? refs]) {
    throw UnimplementedError();
  }

  @override
  Future<void> init() {
    throw UnimplementedError();
  }

  @override
  Future<void> persist(List<Document> docs) {
    throw UnimplementedError();
  }
}
