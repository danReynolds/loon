import 'package:loon/src/persistor/stubs/stub_persistor.dart';

class SqlitePersistor extends StubPersistor {
  SqlitePersistor({
    super.encrypter,
    super.onClear,
    super.onClearAll,
    super.onHydrate,
    super.onPersist,
    super.onSync,
    super.persistenceThrottle,
    super.settings,
    this.useFfi = false,
  });

  final bool useFfi;
}
