import 'dart:async';
import 'dart:js_interop';

import 'package:loon/loon.dart';
import 'package:loon/persistor/data_store.dart';
import 'package:loon/persistor/data_store_encrypter.dart';
import 'package:loon/persistor/data_store_manager.dart';
import 'package:loon/persistor/data_store_persistence_payload.dart';
import 'package:loon/persistor/indexed_db_persistor/indexed_db_data_store_config.dart';
import 'package:loon/persistor/indexed_db_persistor/indexed_db_data_store_resolver.dart';
import 'package:web/web.dart';

typedef IndexedDBTransactionCallback = Future<T> Function<T>(
  String name,
  IDBRequest? Function(IDBObjectStore objectStore) execute,
);

class IndexedDBPersistor extends Persistor {
  static const _dbName = 'loon';
  static const _dbVersion = 1;
  static const _storeName = '__store__';
  static const keyPath = 'key';
  static const valuePath = 'value';

  late final DataStoreManager _manager;
  late final IDBDatabase _db;

  final _logger = Logger('IndexedDBPersistor');

  IndexedDBPersistor({
    super.settings = const PersistorSettings(),
    super.persistenceThrottle = const Duration(milliseconds: 100),
    super.onSync,
  });

  Future<void> _initDB() async {
    final completer = Completer<void>();
    final request = window.indexedDB.open(_dbName, _dbVersion);
    request.onupgradeneeded = ((_) {
      if (_db.objectStoreNames.length == 0) {
        _db.createObjectStore(
          _storeName,
          IDBObjectStoreParameters(keyPath: keyPath.toJS),
        );
      }
    }).toJS;
    request.onerror = ((error) {
      return completer.completeError(
        request.error?.message ?? 'unknown error initializing IndexedDB',
      );
    }).toJS;
    request.onsuccess = ((_) => completer.complete()).toJS;

    await completer.future;

    _db = request.result as IDBDatabase;
  }

  Future<T> _runTransaction<T>(
    String name,
    IDBRequest? Function(IDBObjectStore objectStore) execute,
  ) async {
    final completer = Completer();

    final transaction = _db.transaction(_storeName.toJS);
    final objectStore = transaction.objectStore(_storeName);
    transaction.oncomplete = ((_) => completer.complete()).toJS;
    transaction.onerror = ((_) => completer.completeError('$name error')).toJS;

    final request = execute(objectStore);

    await _logger.measure(name, () => completer.future);

    return request?.result as T;
  }

  @override
  Future<void> init() async {
    final encrypter = DataStoreEncrypter();

    await Future.wait([encrypter.init(), _initDB()]);

    factory(name, encrypted) {
      return DataStore(
        IndexedDBDataStoreConfig(
          encrypted ? '${name}_${DataStoreEncrypter.encryptedName}' : name,
          encrypted: encrypted,
          encrypter: encrypter,
          runTransaction: _runTransaction,
        ),
      );
    }

    final result = await _runTransaction('Init', (objectStore) {
      return objectStore.getAllKeys();
    });
    final initialStoreNames = List<String>.from(result)
        .where((name) => !name.endsWith(DataStoreEncrypter.encryptedName))
        .toSet();

    final resolver =
        IndexedDBDataStoreResolver(runTransaction: _runTransaction);

    await resolver.hydrate();

    _manager = DataStoreManager(
      persistenceThrottle: persistenceThrottle,
      onSync: onSync,
      onLog: _logger.log,
      settings: settings,
      resolver: resolver,
      initialStoreNames: initialStoreNames,
      factory: factory,
    );
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
