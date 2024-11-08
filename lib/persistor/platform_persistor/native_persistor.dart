import 'package:loon/loon.dart';
import 'package:loon/persistor/data_store_encrypter.dart';
import 'package:loon/persistor/file_persistor/file_persistor.dart';

class PlatformPersistor extends FilePersistor {
  PlatformPersistor({
    super.onPersist,
    super.onClear,
    super.onClearAll,
    super.onHydrate,
    super.onSync,
    super.settings = const PersistorSettings(),
    super.persistenceThrottle = const Duration(milliseconds: 100),
    DataStoreEncrypter? encrypter,
  });
}
