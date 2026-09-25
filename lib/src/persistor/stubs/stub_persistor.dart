import 'package:loon/src/json.dart';
import 'package:loon/src/loon.dart';

/// Stands in for a persistor on platforms that don't support it. Stubs take the same constructor
/// parameters as the persistors they replace, so code analyzes the same way on every platform.
class StubPersistor extends Persistor {
  StubPersistor({
    super.encrypter,
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
