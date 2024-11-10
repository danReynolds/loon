import 'dart:io';

import 'package:loon/loon.dart';

class DataStoreResolverConfig {
  final Future<ValueRefStore<String>?> Function() hydrate;
  final Future<void> Function(ValueRefStore<String>) persist;
  final Future<void> Function() delete;
  final Logger logger;

  DataStoreResolverConfig({
    required this.hydrate,
    required this.persist,
    required this.delete,
    Logger? logger,
  }) : logger = logger ?? Logger('DataStoreResolver');
}

/// The data store resolver is persisted alongside the existing data stores and is used to
/// maintain the resolution of documents to their associated data store.
class DataStoreResolver {
  var _store = ValueRefStore<String>();

  static const name = '__resolver__';

  bool isDirty = false;
  bool isHydrated = false;

  final DataStoreResolverConfig config;

  DataStoreResolver(this.config) {
    // Initialize the root of the resolver with the default file data store key.
    // This ensures that all lookups of values in the resolver by parent path roll up
    // to the default store as a fallback if no other value exists for a given path in the resolver.
    _store.write(ValueStore.root, Persistor.defaultKey.value);
  }

  Logger get logger {
    return config.logger;
  }

  bool get isEmpty {
    return _store.isEmpty;
  }

  void writePath(String path, dynamic value) {
    if (_store.get(path) != value) {
      _store.write(path, value);
      isDirty = true;
    }
  }

  void deletePath(
    String path, {
    bool recursive = true,
  }) {
    if (_store.hasValue(path) || recursive && _store.hasPath(path)) {
      _store.delete(path, recursive: recursive);
      isDirty = true;
    }
  }

  Set<String> extractValues(String path) {
    return _store.extractValues(path);
  }

  Map<String, String> extractParentPath(String path) {
    return _store.extractParentPath(path);
  }

  (String, String)? getNearest(String path) {
    return _store.getNearest(path);
  }

  String? get(String path) {
    return _store.get(path);
  }

  Future<void> sync() async {
    if (!isDirty) {
      return;
    }

    if (isEmpty) {
      await delete();
    } else {
      await persist();
    }
  }

  Future<void> hydrate() async {
    if (isHydrated) {
      logger.log('Hydrate canceled. Already hydrated.');
      return;
    }

    final hydratedStore =
        await logger.measure('Hydrate', () => config.hydrate());
    if (hydratedStore != null) {
      _store = hydratedStore;
    }

    isHydrated = true;
  }

  Future<void> persist() async {
    if (isEmpty) {
      logger.log('Canceled persist. Empty store.');
      return;
    }

    if (!isDirty) {
      logger.log('Canceled persist. Clean store.');
      return;
    }

    await logger.measure('Persist', () => config.persist(_store));
    isDirty = false;
  }

  Future<void> delete() async {
    try {
      await logger.measure('Delete', () => config.delete());
      // ignore: empty_catches
    } on PathNotFoundException {}

    _store.clear();
    // Re-initialize the root of the store to the default persistor key.
    _store.write(ValueStore.root, Persistor.defaultKey.value);
  }
}
