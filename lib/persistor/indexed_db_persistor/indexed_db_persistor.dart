import 'dart:async';
import 'dart:js_interop';

import 'package:loon/loon.dart';
import 'package:loon/persistor/data_store_manager.dart';
import 'package:loon/persistor/data_store_persistence_payload.dart';
import 'package:loon/persistor/indexed_db_persistor/indexed_db_data_store.dart';
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

  Future<void> _openDB() async {
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
    final encrypter = await initEncrypter();

    await _openDB();

    final Map<String, IndexedDBDataStore> index = {};

    final result = await _runTransaction('Init', (objectStore) {
      return objectStore.getAllKeys();
    });
    final storeNames = List<String>.from(result);

    for (final name in storeNames) {
      // Only one store needs to be instantiated per plaintext/encrypted entry pair.
      if (!name.endsWith(Persistor.encryptedKey)) {
        index[name] = IndexedDBDataStore(
          name,
          runTransaction: _runTransaction,
          encrypter: encrypter,
        );
      }
    }

    final resolver =
        IndexedDBDataStoreResolver(runTransaction: _runTransaction);

    await resolver.hydrate();

    _manager = DataStoreManager(
      encrypter: encrypter,
      persistenceThrottle: persistenceThrottle,
      onSync: onSync,
      onLog: _logger.log,
      settings: settings,
      resolver: resolver,
      index: index,
      factory: (name) {
        return IndexedDBDataStore(
          name,
          runTransaction: _runTransaction,
          encrypter: encrypter,
        );
      },
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
