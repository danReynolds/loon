import 'package:loon/loon.dart';

class EncryptedFilePersistor extends FilePersistor {
  EncryptedFilePersistor({
    super.persistenceThrottle = const Duration(milliseconds: 100),
    super.settings = const EncryptedFilePersistorSettings(),
    super.onPersist,
    super.onClear,
    super.onClearAll,
    super.onHydrate,
  });
}
