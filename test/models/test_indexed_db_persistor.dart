import 'dart:convert';
import 'dart:js_interop';

import 'package:loon/loon.dart';
import 'package:loon/persistor/data_store_encrypter.dart';
import 'package:loon/persistor/indexed_db_persistor/indexed_db_persistor.dart';

import '../utils.dart';
import 'test_data_store_encrypter.dart';

class TestIndexedDBPersistor extends IndexedDBPersistor {
  static var completer = PersistorCompleter();

  TestIndexedDBPersistor({
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
          encrypter: TestDataStoreEncrypter(),
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

  Future<Map?> getStore(
    String storeName, {
    bool encrypted = false,
  }) async {
    final result = await runTransaction('Get', (objectStore) {
      final objectStoreName = encrypted
          ? '$storeName:${DataStoreEncrypter.encryptedName}'
          : storeName;

      return objectStore.get(objectStoreName.toJS);
    });

    if (result == null) {
      return null;
    }

    final value = result[IndexedDBPersistor.valuePath];

    return jsonDecode(encrypted ? encrypter.decrypt(value) : value);
  }
}
