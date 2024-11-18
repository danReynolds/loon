import 'package:loon/persistor/stubs/stub_persistor.dart';

class FilePersistor extends StubPersistor {
  FilePersistor({
    super.onClear,
    super.onClearAll,
    super.onHydrate,
    super.onPersist,
    super.onSync,
    super.persistenceThrottle,
    super.settings,
  });
}
