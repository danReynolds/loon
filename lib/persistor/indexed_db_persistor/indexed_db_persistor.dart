import 'dart:async';
import 'dart:js_interop';
import 'package:loon/loon.dart';
import 'package:loon/persistor/data_store.dart';
import 'package:loon/persistor/data_store_encrypter.dart';
import 'package:loon/persistor/data_store_manager.dart';
import 'package:loon/persistor/data_store_persistence_payload.dart';
import 'package:loon/persistor/data_store_resolver.dart';
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

  late final DataStoreManager _manager;
  final DataStoreEncrypter encrypter;
  late IDBDatabase _db;

  bool _initialized = false;

  final _logger = Logger('IndexedDBPersistor');

  IndexedDBPersistor({
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

    await _logger.measure(name, () => completer.future);

    return request?.result.dartify() as T;
  }

  @override
  Future<void> init() async {
    await Future.wait([encrypter.init(), _initDB()]);

    final result = await runTransaction('Init', (objectStore) {
      return objectStore.getAllKeys();
    });
    final initialStoreNames = List<String>.from(result)
        .where((name) => name != DataStoreResolver.name)
        .map((name) =>
            name.replaceAll(':${DataStoreEncrypter.encryptedName}', ''))
        .toSet();

    _manager = DataStoreManager(
      persistenceThrottle: persistenceThrottle,
      onSync: onSync,
      onLog: _logger.log,
      settings: settings,
      initialStoreNames: initialStoreNames,
      factory: (name, encrypted) => DataStore(
        IndexedDBDataStoreConfig(
          encrypted ? '$name:${DataStoreEncrypter.encryptedName}' : name,
          encrypted: encrypted,
          encrypter: encrypter,
          runTransaction: runTransaction,
        ),
      ),
      resolverConfig: IndexedDBDataStoreResolverConfig(
        runTransaction: runTransaction,
      ),
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
    return _manager.persist(DataStorePersistencePayload(docs));
  }
}
