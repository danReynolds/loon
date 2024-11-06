import 'dart:convert';
import 'dart:js_interop';
import 'package:loon/loon.dart';
import 'package:loon/persistor/data_store_resolver.dart';
import 'package:loon/persistor/indexed_db_persistor/indexed_db_persistor.dart';

class IndexedDBDataStoreResolver extends DataStoreResolver {
  final IndexedDBTransactionCallback runTransaction;

  IndexedDBDataStoreResolver({
    required this.runTransaction,
  });

  @override
  Future<void> hydrate() async {
    final result = await runTransaction('Hydrate resolver', (objectStore) {
      return objectStore.get(DataStoreResolver.name.toJS);
    });
    store = ValueRefStore<String>(jsonDecode(result));
  }

  @override
  Future<void> persist() {
    return runTransaction('Hydrate resolver', (objectStore) {
      return objectStore.put({
        IndexedDBPersistor.keyPath: DataStoreResolver.name,
        IndexedDBPersistor.valuePath: jsonEncode(store.inspect()),
      }.toJSBox);
    });
  }

  @override
  Future<void> delete() async {
    await runTransaction('Delete resolver', (objectStore) {
      return objectStore.delete(DataStoreResolver.name.toJS);
    });

    store.clear();
    // Re-initialize the root of the store to the default persistor key.
    store.write(ValueStore.root, Persistor.defaultKey.value);
  }
}
