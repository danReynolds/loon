import 'package:flutter/services.dart';
import 'package:loon/persistor/data_store.dart';
import 'package:loon/persistor/data_store_manager.dart';
import 'package:loon/persistor/sqlite_persistor/sqlite_data_store_config.dart';
import 'package:loon/persistor/sqlite_persistor/sqlite_persistor.dart';
import 'package:loon/persistor/worker/persistor_worker.dart';
import 'package:sqflite_common_ffi/sqflite_ffi.dart';

class SqlitePersistorWorkerConfig extends PersistorWorkerConfig {
  final bool useFfi;

  SqlitePersistorWorkerConfig({
    required super.persistenceThrottle,
    required super.settings,
    required super.encrypter,
    required this.useFfi,
  });
}

class SqlitePersistorWorker
    extends PersistorWorker<SqlitePersistorWorkerConfig> {
  SqlitePersistorWorker(super.config);

  static const dbName = 'loon.db';
  static const dbVersion = 1;

  static const tableName = 'store';
  static const keyColumn = 'key';
  static const valueColumn = 'value';

  late final DataStoreManager _manager;

  @override
  init() async {
    // The background isolate binary messenger must be initialized before platform APIs can be invoked.
    BackgroundIsolateBinaryMessenger.ensureInitialized(config.token);

    // In some environments like testing, the Ffi factory must be used to construct the database.
    if (config.useFfi) {
      databaseFactory = databaseFactoryFfi;
    }

    final db = await SqlitePersistor.initDB();

    _manager = DataStoreManager(
      persistenceThrottle: config.persistenceThrottle,
      onSync: onSync,
      logger: logger,
      settings: config.settings,
      encrypter: config.encrypter,
      factory: (name, encrypted, encrypter) => DataStore(
        SqliteDataStoreConfig(
          db: db,
          name,
          encrypted: encrypted,
          encrypter: encrypter,
          logger: logger,
        ),
      ),
      resolverConfig: SqliteDataStoreResolverConfig(db: db),
      clearAll: () => db.delete(SqlitePersistor.tableName),
      getAll: () async {
        final records = await db.query(
          SqlitePersistor.tableName,
          columns: [SqlitePersistor.keyColumn],
        );
        return records
            .map((record) => (record[SqlitePersistor.keyColumn] as String))
            .toList();
      },
    );

    await _manager.init();
  }

  @override
  hydrate(paths) async {
    return _manager.hydrate(paths);
  }

  @override
  persist(payload) {
    return _manager.persist(payload);
  }

  @override
  clear(List<String> collections) {
    return _manager.clear(collections);
  }

  @override
  Future<void> clearAll() {
    return _manager.clearAll();
  }
}
