import 'package:loon/persistor/stubs/stub_persistor.dart';

class SqlitePersistor extends StubPersistor {
  SqlitePersistor({
    super.onClear,
    super.onClearAll,
    super.onHydrate,
    super.onPersist,
    super.onSync,
    super.persistenceThrottle,
    super.settings,
  });
}
