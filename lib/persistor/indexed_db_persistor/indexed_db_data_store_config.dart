import 'dart:convert';
import 'dart:js_interop';
import 'package:loon/loon.dart';
import 'package:loon/persistor/data_store.dart';
import 'package:loon/persistor/indexed_db_persistor/indexed_db_persistor.dart';

class IndexedDBDataStoreConfig extends DataStoreConfig {
  IndexedDBDataStoreConfig(
    super.name, {
    required super.encrypted,
    required super.encrypter,
    required IndexedDBTransactionCallback runTransaction,
  }) : super(
          hydrate: () async {
            final result = await runTransaction('Hydrate', (objectStore) {
              return objectStore.get(name.toJS);
            });

            final value = (result as Map)[IndexedDBPersistor.valuePath];
            final store = ValueStore<ValueStore>();

            for (final entry in value.entries) {
              final resolverPath = entry.key;
              final valueStore = ValueStore.fromJson(entry.value);
              store.write(resolverPath, valueStore);
            }

            return store;
          },
          persist: (store) => runTransaction(
            'Persist',
            (objectStore) {
              final value = jsonEncode(store.extract());

              return objectStore.put({
                IndexedDBPersistor.keyPath: name,
                IndexedDBPersistor.valuePath:
                    encrypted ? encrypter.encrypt(value) : value,
              }.toJSBox);
            },
          ),
          delete: () => runTransaction(
            'Delete',
            (objectStore) => objectStore.delete(name.toJS),
          ),
        );
}
