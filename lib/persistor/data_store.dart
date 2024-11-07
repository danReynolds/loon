import 'dart:io';

import 'package:loon/loon.dart';
import 'package:loon/persistor/data_store_encrypter.dart';

typedef DataStoreFactory = DataStore Function(String name, bool encrypted);

abstract class DataStoreConfig {
  final String name;
  final Logger logger;
  final Future<ValueStore<ValueStore>> Function() hydrate;
  final Future<void> Function(ValueStore<ValueStore>) persist;
  final Future<void> Function() delete;

  DataStoreConfig(
    this.name, {
    required this.hydrate,
    required this.persist,
    required this.delete,
    required bool encrypted,
    required DataStoreEncrypter encrypter,
    final Logger? logger,
  }) : logger = logger ?? Logger('DataStore:$name');
}

class DataStore {
  final DataStoreConfig config;

  var _store = ValueStore<ValueStore>();
  bool isDirty = false;
  bool isHydrated = false;

  DataStore(this.config);

  Logger get logger {
    return config.logger;
  }

  bool get isEmpty {
    return _store.isEmpty;
  }

  /// Returns a map of the subset of documents in the store under the given path.
  /// Data for the given path can exist in two different places:
  /// 1. It necessarily exists in all of the value stores resolved under the given path.
  /// 2. It *could* exist in any of the parent value stores of the given path, such as in the example of the "users"
  ///    path containing data for path users__1, users__1__friends__1, etc.
  Map<String, dynamic> extract([String path = '']) {
    Map<String, dynamic> data = {};

    final parentStores = _store.extractParentPath(path).values;
    final childStores = _store.extractValues(path);

    for (final parentStore in parentStores) {
      data.addAll(parentStore.extract(path));
    }
    for (final childStore in childStores) {
      data.addAll(childStore.extract(path));
    }

    return data;
  }

  void _shallowDelete(
    String resolverPath,
    String path,
  ) {
    final store = _store.get(resolverPath);
    if (store == null || !store.hasValue(path)) {
      return;
    }

    isDirty = true;
    store.delete(path, recursive: false);

    if (store.isEmpty) {
      _store.delete(resolverPath, recursive: false);
    }
  }

  void _recursiveDelete(String path) {
    // 1. Delete the given path from the resolver, evicting all documents under that path that were stored in
    //    resolver paths at or under that path.
    if (_store.hasPath(path)) {
      _store.delete(path);
      isDirty = true;
    }

    // 2. Evict the given path from any parent stores above the given path.
    final valueStores = _store.extractParentPath(path);
    for (final entry in valueStores.entries) {
      final resolverPath = entry.key;
      final valueStore = entry.value;

      if (valueStore.hasPath(path)) {
        valueStore.delete(path);
        isDirty = true;

        if (valueStore.isEmpty) {
          _store.delete(resolverPath, recursive: false);
        }

        // Data under the given path can only exist in one parent path store at a time, so deletion can exit early
        // once a parent path is found.
        break;
      }
    }
  }

  void _graft(
    DataStore otherStore,
    String resolverPath,
    String otherResolverPath,
    String? dataPath,
  ) {
    final otherValueStore = otherStore._store.get(otherResolverPath);
    if (otherValueStore == null) {
      return;
    }

    final valueStore =
        _store.get(resolverPath) ?? _store.write(resolverPath, ValueStore());
    valueStore.graft(otherValueStore, dataPath);
    isDirty = true;

    if (otherValueStore.isEmpty) {
      otherStore._store.delete(otherResolverPath, recursive: false);
    }
  }

  Future<void> hydrate() async {
    if (isHydrated) {
      logger.log('Hydrate canceled. Already hydrated');
      return;
    }

    try {
      _store = await logger.measure('Hydrate', () => config.hydrate());
      // ignore: empty_catches
    } on PathNotFoundException {}

    isHydrated = true;
  }

  Future<void> persist() async {
    if (isEmpty) {
      logger.log('Persist canceled. Empty store');
      return;
    }

    if (!isDirty) {
      logger.log('Persist canceled. Clean store.');
      return;
    }

    await logger.measure('Persist', () => config.persist(_store));
    isDirty = false;
  }

  Future<void> delete() async {
    try {
      await logger.measure('Delete', () => config.delete());
    } on PathNotFoundException {
      return;
    }
  }
}

class DualDataStore {
  final DataStore plaintextStore;
  final DataStore encryptedStore;

  /// The name of the file data store.
  final String name;

  DualDataStore(
    this.name, {
    required DataStore Function(String name, bool encrypted) factory,
  })  : plaintextStore = factory(name, false),
        encryptedStore = factory(name, true);

  bool get isDirty {
    return plaintextStore.isDirty || encryptedStore.isDirty;
  }

  bool get isHydrated {
    return plaintextStore.isHydrated && encryptedStore.isHydrated;
  }

  dynamic get(String resolverPath, String path) {
    return plaintextStore._store.get(resolverPath)?.get(path) ??
        encryptedStore._store.get(resolverPath)?.get(path);
  }

  bool hasValue(String resolverPath, String path) {
    return get(resolverPath, path) != null;
  }

  bool hasPath(String resolverPath, String path) {
    return plaintextStore._store.get(resolverPath)?.hasPath(path) ??
        encryptedStore._store.get(resolverPath)?.hasPath(path) ??
        false;
  }

  /// Returns a map of the subset of documents in the store under the given path.
  /// Data for the given path can exist in two different places:
  /// 1. It necessarily exists in all of the value stores resolved under the given path.
  /// 2. It *could* exist in any of the parent value stores of the given path, such as in the example of the "users"
  ///    path containing data for path users__1, users__1__friends__1, etc.
  Map<String, dynamic> extract([String path = '']) {
    return {
      ...plaintextStore.extract(path),
      ...encryptedStore.extract(path),
    };
  }

  void writePath(
    String? resolverPath,
    String path,
    dynamic value,
    bool encrypted,
  ) async {
    resolverPath ??= '';

    final store = encrypted ? encryptedStore : plaintextStore;
    final otherStore = encrypted ? plaintextStore : encryptedStore;

    // If the document was previously not encrypted and now is or vice-versa, then it should be removed
    // from the other store.
    otherStore._shallowDelete(resolverPath, path);

    store.isDirty = true;
    final valueStore = store._store.get(resolverPath) ??
        store._store.write(resolverPath, ValueStore());
    valueStore.write(path, value);
  }

  /// Deletes the given path from the data store recursively. Documents under the given path could be stored
  /// in one of two places:
  /// 1. In resolver paths under/equal to the given path.
  ///    These documents can easily be deleted by deleting all value stores under the document path in the resolver.
  /// 2. In a resolver path that is a parent path of the given path.
  ///    Ex. When deleting path users__1, all user documents might be stored in resolver path "users", or if no
  ///        custom persistence key has been specified anywhere along the path, then in the default store.
  ///
  ///    Therefore to delete the remaining documents under the given path, each value store in the resolver above the given path is visited
  ///    and has the given path evicted from its store.
  void recursiveDelete(String path) {
    plaintextStore._recursiveDelete(path);
    encryptedStore._recursiveDelete(path);
  }

  /// Shallowly deletes the given path from the given resolver path store.
  void shallowDelete(String resolverPath, String path) {
    plaintextStore._shallowDelete(resolverPath, path);
    encryptedStore._shallowDelete(resolverPath, path);
  }

  bool get isEmpty {
    return plaintextStore.isEmpty && encryptedStore.isEmpty;
  }

  /// Grafts the data in the given [other] data store under resolver path [otherResolverPath] and data path [dataPath]
  /// into this data store under resolver path [resolverPath] at data path [dataPath].
  void graft(
    String resolverPath,
    String otherResolverPath,
    String? dataPath,
    DualDataStore other,
  ) {
    plaintextStore._graft(
      other.plaintextStore,
      resolverPath,
      otherResolverPath,
      dataPath,
    );
    encryptedStore._graft(
      other.encryptedStore,
      resolverPath,
      otherResolverPath,
      dataPath,
    );
  }

  Map inspect() {
    return {
      "plaintext": plaintextStore._store.inspect(),
      "encrypted": encryptedStore._store.inspect(),
    };
  }

  Future<void> hydrate() async {
    await Future.wait([
      plaintextStore.hydrate(),
      encryptedStore.hydrate(),
    ]);
  }

  Future<void> persist() async {
    await Future.wait([
      plaintextStore.persist(),
      encryptedStore.persist(),
    ]);
  }

  Future<void> delete() async {
    await Future.wait([
      plaintextStore.delete(),
      encryptedStore.delete(),
    ]);
  }

  Future<void> sync() async {
    if (isEmpty) {
      await delete();
    } else if (isDirty) {
      await persist();
    }
  }
}
