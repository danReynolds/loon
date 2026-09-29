import 'package:loon/src/json.dart';
import 'package:loon/src/loon.dart';

/// Stands in for a persistor on platforms that don't support it. The analyzer always resolves
/// `package:loon/loon.dart`'s persistor exports to these stubs, so they take the same constructor
/// parameters as the persistors they replace. Other persistor members are internal.
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
