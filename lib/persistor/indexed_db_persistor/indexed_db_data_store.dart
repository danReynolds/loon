import 'dart:async';
import 'dart:convert';
import 'dart:js_interop';
import 'package:loon/loon.dart';
import 'package:loon/persistor/data_store.dart';
import 'package:loon/persistor/indexed_db_persistor/indexed_db_persistor.dart';
import 'package:web/web.dart';

class IndexedDBDataStore extends DataStore {
  final IndexedDBTransactionCallback runTransaction;

  IndexedDBDataStore(
    super.name, {
    required this.runTransaction,
    required super.encrypter,
  });

  String _getKeyName(DataStoreValueStore valueStore) {
    return valueStore.encrypted ? '${name}_${Persistor.encryptedKey}' : name;
  }

  Future<String?> _readObject(
    IDBObjectStore objectStore,
    DataStoreValueStore valueStore,
  ) async {
    final completer = Completer<void>();
    final request = objectStore.get(_getKeyName(valueStore).toJS);
    request.onsuccess = ((_) => completer.complete()).toJS;
    request.onerror =
        ((_) => completer.completeError('Read error: $name')).toJS;

    await completer.future;

    return (request.result as Map)[IndexedDBPersistor.valuePath];
  }

  void _writeObject(
    IDBObjectStore objectStore,
    DataStoreValueStore valueStore,
  ) {
    objectStore.put({
      IndexedDBPersistor.keyPath: _getKeyName(valueStore),
      IndexedDBPersistor.valuePath: jsonEncode(valueStore.inspect()),
    }.toJSBox);
  }

  Future<void> _hydrate(
    IDBObjectStore objectStore,
    DataStoreValueStore valueStore,
  ) async {
    final value = await _readObject(objectStore, valueStore);
    if (value != null) {
      final Map json =
          jsonDecode(valueStore.encrypted ? decrypt(value) : value);

      for (final entry in json.entries) {
        final resolverPath = entry.key;
        final valueStore = ValueStore.fromJson(entry.value);
        plaintextStore.write(resolverPath, valueStore);
      }
    }
  }

  @override
  Future<void> hydrate() async {
    return runTransaction('Hydrate', (objectStore) {
      _hydrate(objectStore, plaintextStore);
      _hydrate(objectStore, encryptedStore);
      return null;
    });
  }

  @override
  Future<void> persist() async {
    return runTransaction(
      'Persist',
      (objectStore) {
        if (plaintextStore.isDirty) {
          _writeObject(objectStore, plaintextStore);
        }

        if (encryptedStore.isDirty) {
          _writeObject(objectStore, encryptedStore);
        }
        return null;
      },
    );
  }

  @override
  Future<void> delete() {
    return runTransaction(
      'Delete',
      (objectStore) {
        objectStore.delete(_getKeyName(plaintextStore).toJS);
        objectStore.delete(_getKeyName(encryptedStore).toJS);
        return null;
      },
    );
  }
}
