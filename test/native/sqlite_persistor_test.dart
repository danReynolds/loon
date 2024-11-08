import 'dart:convert';
import 'package:flutter_test/flutter_test.dart';
import 'package:loon/persistor/data_store_encrypter.dart';
import 'package:loon/persistor/sqlite_persistor/sqlite_persistor.dart';
import '../core/persistor/persistor_test_runner.dart';

import 'package:sqflite_common_ffi/sqflite_ffi.dart';

void main() {
  sqfliteFfiInit();
  // Change the default factory for unit testing calls for SQFlite.
  databaseFactory = databaseFactoryFfi;

  group('SqlitePersistor', () {
    persistorTestRunner<SqlitePersistor>(
      getStore: (
        persistor,
        storeName, {
        bool encrypted = false,
      }) async {
        final key = encrypted
            ? '$storeName:${DataStoreEncrypter.encryptedName}'
            : storeName;

        final records = await persistor.db.query(
          SqlitePersistor.tableName,
          columns: [SqlitePersistor.valueColumn],
          where: '${SqlitePersistor.keyColumn} = ?',
          whereArgs: [key],
        );

        if (records.isEmpty) {
          return null;
        }

        final value = records.first[SqlitePersistor.valueColumn] as String;

        return jsonDecode(
          encrypted ? persistor.encrypter.decrypt(value) : value,
        );
      },
      factory: SqlitePersistor.new,
    );
  });
}
