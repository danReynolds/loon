import 'package:loon/loon.dart';
import 'package:loon/persistor/sqlite_persistor/sqlite_persistor_worker.dart';
import 'package:loon/persistor/worker/persistor_worker_mixin.dart';
import 'package:sqflite/sqflite.dart';
import 'package:path/path.dart';

class SqlitePersistor extends Persistor with PersistorWorkerMixin {
  static const dbName = 'loon.db';
  static const dbVersion = 1;

  static const tableName = 'store';
  static const keyColumn = 'key';
  static const valueColumn = 'value';

  /// Whether to use the FFI database factory. This is necessary for certain environments
  /// such as testing.
  final bool useFfi;

  SqlitePersistor({
    super.onPersist,
    super.onClear,
    super.onClearAll,
    super.onHydrate,
    super.encrypter,
    super.settings = const PersistorSettings(),
    super.persistenceThrottle = const Duration(milliseconds: 100),
    super.onSync,
    this.useFfi = false,
  }) : super(logger: Loon.logger.child('SqlitePersistor'));

  /// Initializes the database on the current isolate. Used by both the worker and test environment
  /// for accessing data from the DB.
  static Future<Database> initDB() async {
    final databasesPath = await getDatabasesPath();
    String path = join(databasesPath, dbName);

    return openDatabase(
      path,
      version: dbVersion,
      singleInstance: false,
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
    await spawnWorker(
      SqlitePersistorWorker.new,
      config: SqlitePersistorWorkerConfig(
        useFfi: useFfi,
        persistenceThrottle: persistenceThrottle,
        settings: settings,
        encrypter: encrypter,
      ),
    );
  }

  @override
  hydrate([refs]) async {
    return worker.hydrate(refs);
  }

  @override
  persist(docs) async {
    return worker.persist(docs);
  }

  @override
  clear(collections) async {
    return worker.clear(collections);
  }

  @override
  clearAll() async {
    return worker.clearAll();
  }
}
