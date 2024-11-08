import 'dart:convert';
import 'dart:js_interop';

import 'package:flutter_test/flutter_test.dart';
import 'package:loon/persistor/data_store_encrypter.dart';
import 'package:loon/persistor/indexed_db_persistor/indexed_db_persistor.dart';
import '../core/persistor/persistor_test_runner.dart';

void main() {
  TestWidgetsFlutterBinding.ensureInitialized();

  persistorTestRunner<IndexedDBPersistor>(
    getStore: (
      persistor,
      storeName, {
      bool encrypted = false,
    }) async {
      final result = await persistor.runTransaction('Get', (objectStore) {
        final objectStoreName = encrypted
            ? '$storeName:${DataStoreEncrypter.encryptedName}'
            : storeName;

        return objectStore.get(objectStoreName.toJS);
      });

      if (result == null) {
        return null;
      }

      final value = result[IndexedDBPersistor.valuePath];

      return jsonDecode(encrypted ? persistor.encrypter.decrypt(value) : value);
    },
    factory: IndexedDBPersistor.new,
  );
}
