import 'package:loon/loon.dart';

class StubPersistor extends Persistor {
  StubPersistor({
    super.onClear,
    super.onClearAll,
    super.onHydrate,
    super.onPersist,
    super.onSync,
    super.persistenceThrottle,
    super.settings,
  }) : super(logger: Logger('StubPersistor'));

  @override
  Future<void> clear(refs) {
    throw UnimplementedError();
  }

  @override
  Future<void> clearAll() {
    throw UnimplementedError();
  }

  @override
  Future<Json> hydrate([refs]) {
    throw UnimplementedError();
  }

  @override
  Future<void> init() {
    throw UnimplementedError();
  }

  @override
  Future<void> persist(docs) {
    throw UnimplementedError();
  }
}
