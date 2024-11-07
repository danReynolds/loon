import 'dart:convert';
import 'dart:js_interop';
import 'package:loon/loon.dart';
import 'package:loon/persistor/data_store.dart';
import 'package:loon/persistor/data_store_resolver.dart';
import 'package:loon/persistor/indexed_db_persistor/indexed_db_persistor.dart';

class IndexedDBDataStoreConfig extends DataStoreConfig {
  IndexedDBDataStoreConfig(
    super.name, {
    required super.encrypted,
    required super.encrypter,
    required IndexedDBTransactionCallback runTransaction,
  }) : super(
          hydrate: () async {
            final result =
                await runTransaction('Hydrate store: $name', (objectStore) {
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
            'Persist store: $name',
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
            'Delete store: $name',
            (objectStore) => objectStore.delete(name.toJS),
          ),
        );
}

class IndexedDBDataStoreResolverConfig extends DataStoreResolverConfig {
  static const name = DataStoreResolver.name;

  IndexedDBDataStoreResolverConfig({
    required IndexedDBTransactionCallback runTransaction,
  }) : super(
          hydrate: () async {
            final result =
                await runTransaction('Hydrate resolver', (objectStore) {
              return objectStore.get(name.toJS);
            });

            final value = (result as Map)[IndexedDBPersistor.valuePath];
            return ValueRefStore(value);
          },
          persist: (store) => runTransaction(
            'Persist resolver',
            (objectStore) {
              final value = jsonEncode(store.extract());

              return objectStore.put({
                IndexedDBPersistor.keyPath: name,
                IndexedDBPersistor.valuePath: value,
              }.toJSBox);
            },
          ),
          delete: () => runTransaction(
            'Delete resolver',
            (objectStore) => objectStore.delete(name.toJS),
          ),
        );
}
