import 'package:loon/loon.dart';

abstract class DataStoreResolver {
  var store = ValueRefStore<String>();

  static const name = '_store__';

  bool isDirty = false;

  DataStoreResolver() {
    // Initialize the root of the resolver with the default file data store key.
    // This ensures that all lookups of values in the resolver by parent path roll up
    // to the default store as a fallback if no other value exists for a given path in the resolver.
    store.write(ValueStore.root, Persistor.defaultKey.value);
  }

  void writePath(String path, dynamic value) {
    if (store.hasPath(path) != value) {
      store.write(path, value);
      isDirty = true;
    }
  }

  void deletePath(
    String path, {
    bool recursive = true,
  }) {
    if (store.hasValue(path) || recursive && store.hasPath(path)) {
      store.delete(path, recursive: recursive);
      isDirty = true;
    }
  }

  Set<String> extractValues(String path) {
    return store.getRefs(path)?.keys.toSet() ?? {};
  }

  Map<String, String> extractParentPath(String path) {
    return store.extractParentPath(path);
  }

  (String, String)? getNearest(String path) {
    return store.getNearest(path);
  }

  String? get(String path) {
    return store.get(path);
  }

  Future<void> hydrate();

  Future<void> persist();

  Future<void> sync();

  Future<void> delete();
}
