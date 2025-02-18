import 'dart:convert';
import 'package:loon/loon.dart';
import 'package:loon/persistor/data_store.dart';
import 'package:loon/persistor/data_store_resolver.dart';
import 'package:loon/persistor/sqlite_persistor/sqlite_persistor.dart';
import 'package:sqflite/sqflite.dart';

const _tableName = SqlitePersistor.tableName;
const _keyColumn = SqlitePersistor.keyColumn;
const _valueColumn = SqlitePersistor.valueColumn;

class SqliteDataStoreConfig extends DataStoreConfig {
  SqliteDataStoreConfig(
    super.name, {
    required Database db,
    required super.encrypted,
    required super.encrypter,
    required super.logger,
  }) : super(
          hydrate: () async {
            final rows = await db.query(
              _tableName,
              columns: [_valueColumn],
              where: '$_keyColumn = ?',
              whereArgs: [name],
            );

            if (rows.isEmpty) {
              return null;
            }

            final value = rows.first[_valueColumn] as String;

            final json =
                jsonDecode(encrypted ? encrypter.decrypt(value) : value);
            final store = ValueStore<ValueStore>();

            for (final entry in json.entries) {
              final resolverPath = entry.key;
              final valueStore = ValueStore.fromJson(entry.value);
              store.write(resolverPath, valueStore);
            }

            return store;
          },
          persist: (store) async {
            final value = jsonEncode(store.extract());

            await db.insert(
              _tableName,
              {
                _keyColumn: name,
                _valueColumn: encrypted ? encrypter.encrypt(value) : value,
              },
              conflictAlgorithm: ConflictAlgorithm.replace,
            );
          },
          delete: () async {
            await db.delete(
              _tableName,
              where: '$_keyColumn = ?',
              whereArgs: [name],
            );
          },
        );
}

class SqliteDataStoreResolverConfig extends DataStoreResolverConfig {
  static const name = DataStoreResolver.name;

  SqliteDataStoreResolverConfig({
    required Database db,
    required super.logger,
  }) : super(
          hydrate: () async {
            final rows = await db.query(
              _tableName,
              columns: [_valueColumn],
              where: '$_keyColumn = ?',
              whereArgs: [name],
            );

            if (rows.isEmpty) {
              return null;
            }

            final json = jsonDecode(rows.first[_valueColumn] as String);
            return ValueRefStore<String>(json);
          },
          persist: (store) => db.insert(
            _tableName,
            {
              _keyColumn: name,
              _valueColumn: jsonEncode(store.inspect()),
            },
            conflictAlgorithm: ConflictAlgorithm.replace,
          ),
          delete: () async {
            await db.delete(
              _tableName,
              where: '$_keyColumn = ?',
              whereArgs: [name],
            );
          },
        );
}
