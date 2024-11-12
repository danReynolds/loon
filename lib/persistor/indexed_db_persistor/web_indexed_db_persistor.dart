import 'dart:async';
import 'dart:js_interop';
import 'package:loon/loon.dart';
import 'package:loon/persistor/data_store.dart';
import 'package:loon/persistor/data_store_manager.dart';
import 'package:loon/persistor/persist_payload.dart';
import 'package:loon/persistor/indexed_db_persistor/indexed_db_data_store_config.dart';
import 'package:web/web.dart';

typedef IndexedDBTransactionCallback = Future<T> Function<T>(
  String name,
  IDBRequest? Function(IDBObjectStore objectStore) execute, [
  IDBTransactionMode mode,
]);

class IndexedDBPersistor extends Persistor {
  static const _dbName = 'loon';
  static const _dbVersion = 1;
  static const _storeName = 'store';
  static const keyPath = 'key';
  static const valuePath = 'value';

  late IDBDatabase _db;
  late final DataStoreManager _manager;

  bool _initialized = false;

  IndexedDBPersistor({
    super.onPersist,
    super.onClear,
    super.onClearAll,
    super.onHydrate,
    super.encrypter,
    super.settings = const PersistorSettings(),
    super.persistenceThrottle = const Duration(milliseconds: 100),
    super.onSync,
  }) : super(logger: Loon.logger.child('IndexedDBPersistor'));

  Future<void> _initDB() async {
    final completer = Completer<void>();
    final request = window.indexedDB.open(_dbName, _dbVersion);
    request.onupgradeneeded = ((Event _) {
      // If an upgrade is needed, then the DB can be set earlier in the request lifecycle
      // when the upgrade is processed, otherwise it is set when the request completes below.
      _db = request.result as IDBDatabase;

      if (!_initialized) {
        _db = request.result as IDBDatabase;
        _initialized = true;
      }

      if (_db.objectStoreNames.length == 0) {
        _db.createObjectStore(
          _storeName,
          IDBObjectStoreParameters(keyPath: keyPath.toJS),
        );
      }
    }).toJS;
    request.onerror = ((ExternalDartReference error) {
      return completer.completeError(
        request.error?.message ?? 'unknown error initializing IndexedDB',
      );
    }).toJS;
    request.onsuccess =
        ((ExternalDartReference _) => completer.complete()).toJS;

    await completer.future;

    _db = request.result as IDBDatabase;
  }

  Future<T> runTransaction<T>(
    String name,
    IDBRequest? Function(IDBObjectStore objectStore) execute, [
    IDBTransactionMode mode = 'readonly',
  ]) async {
    final completer = Completer();

    final transaction = _db.transaction(_storeName.toJS, mode);
    final objectStore = transaction.objectStore(_storeName);
    transaction.oncomplete =
        ((ExternalDartReference _) => completer.complete()).toJS;
    transaction.onerror = ((ExternalDartReference _) =>
        completer.completeError('$name error')).toJS;

    final request = execute(objectStore);

    await logger.measure(name, () => completer.future);

    return request?.result.dartify() as T;
  }

  @override
  Future<void> init() async {
    await _initDB();

    _manager = DataStoreManager(
      persistenceThrottle: persistenceThrottle,
      onSync: onSync,
      logger: logger,
      settings: settings,
      encrypter: encrypter,
      factory: (name, encrypted, encrypter) => DataStore(
        IndexedDBDataStoreConfig(
          name,
          logger: logger,
          encrypted: encrypted,
          encrypter: encrypter,
          runTransaction: runTransaction,
        ),
      ),
      resolverConfig: IndexedDBDataStoreResolverConfig(
        runTransaction: runTransaction,
      ),
      clearAll: () => runTransaction(
        'clearAll',
        (objectStore) => objectStore.clear(),
        'readwrite',
      ),
      getAll: () async {
        final result = await runTransaction(
          'GetAll',
          (objectStore) => objectStore.getAllKeys(),
        );
        return List<String>.from(result);
      },
    );

    await _manager.init();
  }

  @override
  clear(List<Collection> collections) {
    return _manager.clear(
      collections.map((collection) => collection.path).toList(),
    );
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
    return _manager.persist(PersistPayload(docs));
  }
}
