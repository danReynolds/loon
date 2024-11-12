import 'dart:convert';
import 'dart:js_interop';

import 'package:flutter_test/flutter_test.dart';
import 'package:loon/persistor/indexed_db_persistor/web_indexed_db_persistor.dart';
import '../core/persistor/persistor_test_runner.dart';

void main() {
  TestWidgetsFlutterBinding.ensureInitialized();

  persistorTestRunner<IndexedDBPersistor>(
    getStore: (
      persistor,
      storeName, {
      required encrypted,
    }) async {
      final result = await persistor.runTransaction('Get', (objectStore) async {
        return objectStore.get(storeName.toJS);
      });

      if (result == null) {
        return null;
      }

      final value = result[IndexedDBPersistor.valuePath];

      return jsonDecode(
        encrypted ? await persistor.encrypter.decrypt(value) : value,
      );
    },
    factory: IndexedDBPersistor.new,
  );
}
