import 'package:loon/src/persistor/stubs/stub_persistor.dart';

class FilePersistor extends StubPersistor {
  FilePersistor({
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
