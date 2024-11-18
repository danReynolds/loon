import 'package:loon/persistor/stubs/stub_persistor.dart';

class IndexedDBPersistor extends StubPersistor {
  IndexedDBPersistor({
    super.onClear,
    super.onClearAll,
    super.onHydrate,
    super.onPersist,
    super.onSync,
    super.persistenceThrottle,
    super.settings,
  });
}
