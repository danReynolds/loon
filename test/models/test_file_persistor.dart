import 'package:encrypt/encrypt.dart';
import 'package:loon/loon.dart';
import 'package:loon/persistor/data_store_encrypter.dart';
import 'package:loon/persistor/file_persistor/file_persistor.dart';

import '../utils.dart';

class _TestDataStoreEncrypter extends DataStoreEncrypter {
  @override
  init() async {
    encrypter = Encrypter(AES(testEncryptionKey, mode: AESMode.cbc));
  }

  @override
  String decrypt(String encrypted) {
    final iv = IV.fromBase64(encrypted.substring(0, 24));
    return encrypter.decrypt64(
      encrypted.substring(24),
      iv: iv,
    );
  }
}

class TestFilePersistor extends FilePersistor {
  static FilePersistorCompleter completer = FilePersistorCompleter();

  TestFilePersistor({
    PersistorSettings? settings,
    void Function(Set<Document> batch)? onPersist,
    void Function(Set<Collection> collections)? onClear,
    void Function()? onClearAll,
    void Function(Json data)? onHydrate,
    void Function()? onSync,
  }) : super(
          // To make tests run faster, in the test environment the persistence throttle
          // is decreased to 1 millisecond.
          persistenceThrottle: const Duration(milliseconds: 1),
          settings: settings ?? const PersistorSettings(),
          encrypter: _TestDataStoreEncrypter(),
          onPersist: (docs) {
            onPersist?.call(docs);
            completer.persistComplete();
          },
          onHydrate: (refs) {
            onHydrate?.call(refs);
            completer.hydrateComplete();
          },
          onClear: (collections) {
            onClear?.call(collections);
            completer.clearComplete();
          },
          onClearAll: () {
            onClearAll?.call();
            completer.clearAllComplete();
          },
          onSync: () {
            onSync?.call();
            completer.syncComplete();
          },
        );
}
