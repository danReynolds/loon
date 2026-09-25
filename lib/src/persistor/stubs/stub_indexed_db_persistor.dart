import 'package:loon/src/persistor/stubs/stub_persistor.dart';

class IndexedDBPersistor extends StubPersistor {
  IndexedDBPersistor({
    super.encrypter,
    super.onClear,
    super.onClearAll,
    super.onHydrate,
    super.onPersist,
    super.onSync,
    super.persistenceThrottle,
    super.settings,
  });
}
