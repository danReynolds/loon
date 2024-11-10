import 'package:loon/loon.dart';
import 'package:loon/persistor/data_store.dart';
import 'package:loon/persistor/data_store_encrypter.dart';
import 'package:loon/persistor/data_store_manager.dart';
import 'package:loon/persistor/data_store_persistence_payload.dart';
import 'package:loon/persistor/sqlite_persistor/sqlite_data_store_config.dart';
import 'package:path/path.dart';
import 'package:sqflite/sqflite.dart';

class SqlitePersistor extends Persistor {
  static const dbName = 'loon.db';
  static const dbVersion = 1;

  static const tableName = 'store';
  static const keyColumn = 'key';
  static const valueColumn = 'value';

  final _logger = Loon.logger.child('SqlitePersistor');

  late final DataStoreManager _manager;
  final DataStoreEncrypter encrypter;
  late final Database db;

  SqlitePersistor({
    super.onPersist,
    super.onClear,
    super.onClearAll,
    super.onHydrate,
    super.settings = const PersistorSettings(),
    super.persistenceThrottle = const Duration(milliseconds: 100),
    super.onSync,
    DataStoreEncrypter? encrypter,
  }) : encrypter = encrypter ?? DataStoreEncrypter();

  Future<void> _initDB() async {
    final databasesPath = await getDatabasesPath();
    String path = join(databasesPath, dbName);

    db = await openDatabase(
      path,
      version: dbVersion,
      onCreate: (db, version) async {
        await db.execute(
          '''
          CREATE TABLE $tableName (
            $keyColumn TEXT PRIMARY KEY,
            $valueColumn TEXT
          )
          ''',
        );
      },
    );
  }

  @override
  Future<void> init() async {
    await Future.wait([encrypter.init(), _initDB()]);

    _manager = DataStoreManager(
      persistenceThrottle: persistenceThrottle,
      onSync: onSync,
      logger: _logger,
      settings: settings,
      factory: (name, encrypted) => DataStore(
        SqliteDataStoreConfig(
          db: db,
          name,
          encrypted: encrypted,
          encrypter: encrypter,
          logger: _logger,
        ),
      ),
      resolverConfig: SqliteDataStoreResolverConfig(db: db),
      clearAll: () => db.delete(tableName),
      getAll: () async {
        final records = await db.query(tableName, columns: [keyColumn]);
        return records.map((record) => (record[keyColumn] as String)).toList();
      },
    );

    await _manager.init();
  }

  @override
  clear(List<Collection> collections) {
    return _manager
        .clear(collections.map((collection) => collection.path).toList());
  }

  @override
  clearAll() {
    return _manager.clearAll();
  }

  @override
  hydrate([refs]) {
    return _manager.hydrate(refs?.map((ref) => ref.path).toList());
  }

  @override
  persist(docs) {
    return _manager.persist(DataStorePersistencePayload(docs));
  }
}
