import 'dart:convert';
import 'dart:js_interop';
import 'package:loon/loon.dart';
import 'package:loon/persistor/data_store.dart';
import 'package:loon/persistor/data_store_resolver.dart';
import 'package:loon/persistor/indexed_db_persistor/web_indexed_db_persistor.dart';

class IndexedDBDataStoreConfig extends DataStoreConfig {
  IndexedDBDataStoreConfig(
    super.name, {
    required super.encrypted,
    required super.encrypter,
    required super.logger,
    required IndexedDBTransactionCallback runTransaction,
  }) : super(
          hydrate: () async {
            final result = await runTransaction(
              'Hydrate store: $name',
              (objectStore) {
                return objectStore.get(name.toJS);
              },
            );

            if (result == null) {
              return null;
            }

            final value = result[IndexedDBPersistor.valuePath];
            final json =
                jsonDecode(encrypted ? encrypter.decrypt(value) : value);

            final store = ValueStore<ValueStore>();

            for (final entry in json.entries) {
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
              }.jsify());
            },
            'readwrite',
          ),
          delete: () => runTransaction(
            'Delete store: $name',
            (objectStore) => objectStore.delete(name.toJS),
            'readwrite',
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

            if (result == null) {
              return null;
            }

            final json = jsonDecode(result[IndexedDBPersistor.valuePath]);

            return ValueRefStore<String>(json);
          },
          persist: (store) => runTransaction(
            'Persist resolver',
            (objectStore) {
              return objectStore.put({
                IndexedDBPersistor.keyPath: name,
                IndexedDBPersistor.valuePath: jsonEncode(store.inspect()),
              }.jsify());
            },
            'readwrite',
          ),
          delete: () => runTransaction(
            'Delete resolver',
            (objectStore) => objectStore.delete(name.toJS),
            'readwrite',
          ),
        );
}
