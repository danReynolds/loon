import 'dart:convert';
import 'package:flutter_test/flutter_test.dart';
import 'package:loon/persistor/sqlite_persistor/sqlite_persistor.dart';
import '../core/persistor/persistor_test_runner.dart';
import 'package:sqflite_common_ffi/sqflite_ffi.dart';

void main() {
  sqfliteFfiInit();
  // Change the default factory for unit testing calls for SQFlite.
  databaseFactory = databaseFactoryFfi;

  group(
    'SqlitePersistor',
    () {
      persistorTestRunner<SqlitePersistor>(
        getStore: (
          persistor,
          storeName, {
          required encrypted,
        }) async {
          final db = await SqlitePersistor.initDB();
          final records = await db.query(
            SqlitePersistor.tableName,
            columns: [SqlitePersistor.valueColumn],
            where: '${SqlitePersistor.keyColumn} = ?',
            whereArgs: [storeName],
          );

          if (records.isEmpty) {
            return null;
          }

          final value = records.first[SqlitePersistor.valueColumn] as String;

          return jsonDecode(
              encrypted ? persistor.encrypter.decrypt(value) : value);
        },
        factory: ({
          encrypter,
          onClear,
          onClearAll,
          onHydrate,
          onPersist,
          onSync,
          required persistenceThrottle,
          required settings,
        }) =>
            SqlitePersistor(
          encrypter: encrypter,
          onClear: onClear,
          onClearAll: onClearAll,
          onHydrate: onHydrate,
          onPersist: onPersist,
          onSync: onSync,
          persistenceThrottle: persistenceThrottle,
          settings: settings,
          useFfi: true,
        ),
      );
    },
  );
}
