import 'dart:io';
import 'package:encrypt/encrypt.dart';
import 'package:loon/loon.dart';
import 'package:loon/persistor/file_persistor/file_data_store.dart';
import 'package:loon/persistor/file_persistor/file_persist_document.dart';
import 'package:loon/persistor/file_persistor/file_persistor_settings.dart';
import 'package:path/path.dart' as path;

class FileDataStoreManager {
  final Encrypter encrypter;

  /// The directory in which a file data store is persisted.
  final Directory directory;

  /// The resolver that contains a mapping of documents to the file data store in which
  /// the document is currently stored.
  late final FileDataStoreResolver _resolver;

  /// The index of [FileDataStore] objects by name.
  final Map<String, DualFileDataStore> _index = {};

  FileDataStoreManager({
    required this.directory,
    required this.encrypter,
  });

  /// Resolves the data store name for the given path as the nearest value found working up from
  /// the full path, falling back to the default store key if none is found.
  String _resolveStoreName(String path) {
    return _resolver.store.getNearest(path) ?? FileDataStore.defaultKey;
  }

  /// Resolves the set of [FileDataStore] that exist at the given path and under it.
  Set<DualFileDataStore> _resolveStores(String path) {
    // Resolve the store for the document path itself separately.
    final store = _index[_resolveStoreName(path)];

    return {
      if (store != null) store,
      // Then resolve all of the data stores under the given path.
      //
      // Traversing the resolver tree to extract the set of data stores referenced under a given path is generally performant,
      // since the number of nodes traversed in the resolver tree scales O(m) where m is the number of distinct collections that
      // specify a unique persistence key under the given path and is generally small.
      ..._resolver.store
          .extractRefs(path)
          .keys
          .map((name) => _index[name]!)
          .toSet(),
    };
  }

  /// Syncs all file data stores, persisting dirty ones and deleting ones that can now be removed.
  Future<void> _sync() async {
    final dirtyStores =
        _index.values.where((dataStore) => dataStore.isDirty).toList();

    if (dirtyStores.isEmpty) {
      return;
    }

    await Future.wait([
      ...dirtyStores.map((store) => store.sync()),
      _resolver.persist(),
    ]);

    for (final store in dirtyStores) {
      if (store.isEmpty) {
        _index.remove(store.name);
      }
    }
  }

  /// Clears the provided path and all of its subpaths from each data store that contains
  /// data under that path.
  Future<void> _clear(String path) async {
    final stores = _resolveStores(path);

    await Future.wait(stores.map((store) => store.deletePath(path)));

    _resolver.store.delete(path);
  }

  Future<void> init() async {
    // Initialize all file data stores.
    final files = directory
        .listSync()
        .whereType<File>()
        .where((file) => fileRegex.hasMatch(path.basename(file.path)))
        .toList();
    for (final file in files) {
      final dataStore = DualFileDataStore.parse(
        file,
        encrypter: encrypter,
        directory: directory,
      );
      final dataStoreName = dataStore.name;

      if (!_index.containsKey(dataStoreName)) {
        _index[dataStoreName] = dataStore;
      }
    }

    // Initialize and immediately hydrate the resolver data, since it is required
    // for processing subsequent data store hydrate/persist operations.
    _resolver = FileDataStoreResolver(directory: directory);
    await _resolver.hydrate();
  }

  /// Hydrates the given paths and returns a map of document paths to their serialized data.
  Future<Map<String, Json>> hydrate(List<String>? paths) async {
    final Map<String, Set<DualFileDataStore>> pathDataStores = {};
    final Set<DualFileDataStore> dataStores = {};

    // If the hydration operation is only for certain paths, then resolve all of the file data stores
    // relevant to the given paths and their subpaths and hydrate those data stores.
    if (paths != null) {
      for (final path in paths) {
        final stores = _resolveStores(path);
        pathDataStores[path] = stores;
        dataStores.addAll(stores);
      }
    } else {
      // If no specific collections have been specified, then hydrate all file data stores.
      dataStores.addAll(_index.values);
    }

    await Future.wait(dataStores.map((store) => store.hydrate()));

    final Map<String, Json> data = {};
    if (paths != null) {
      for (final path in paths) {
        for (final dataStore in pathDataStores[path]!) {
          // Since many different paths can be contained within the same file data store,
          // we only extract the data in the hydrated store that falls under the requested path.
          //
          // Doing this ensures that the client's contract to only hydrate the data that the requested
          // is fulfilled and it also offers a performance benefit since no unnecessary data is copied
          // back from the worker to the main isolate.
          //
          // If later on the client requests to hydrate a path for a data store that has already been
          // hydrated but has not yet delivered the data under that path to the client, then this still
          // works as expected, as the hydration operation will just extract that data from the already hydrated
          // data store and deliver it to the client as expected.
          final (plaintextData, encryptedData) = dataStore.extractValues(path);
          data.addAll(plaintextData);
          data.addAll(encryptedData);
        }
      }
    } else {
      for (final dataStore in dataStores) {
        final (plaintextData, encryptedData) = dataStore.extractValues();
        data.addAll(plaintextData);
        data.addAll(encryptedData);
      }
    }

    return data;
  }

  Future<void> persist(List<FilePersistDocument> docs) async {
    if (docs.isEmpty) {
      return;
    }

    for (final doc in docs) {
      final collectionPath = doc.parent;
      final docPath = doc.path;
      final docData = doc.data;
      final persistenceKey = doc.key;
      final encrypted = doc.encrypted;

      // If the document has been deleted, then clear it and its subcollections from the store.
      if (docData == null) {
        await _clear(docPath);
        continue;
      }

      final prevDataStoreName = _resolveStoreName(docPath);
      final prevDataStore = _index[prevDataStoreName];

      // If the persistence key for the document is now null, then remove the previous
      // key for the document (if it exists) ahead of resolving its data store name.
      if (persistenceKey == null) {
        _resolver.store.delete(docPath, recursive: false);
      }

      final dataStoreName = persistenceKey?.value ?? _resolveStoreName(docPath);
      final dataStore = _index[dataStoreName] ??= DualFileDataStore(
        name: dataStoreName,
        encrypter: encrypter,
        directory: directory,
        isHydrated: true,
      );

      // If the resolved data store for the document has changed, then its data
      // should be grafted from its previous data store to the updated one.
      if (prevDataStore != null && prevDataStore != dataStore) {
        await dataStore.graft(prevDataStore, docPath);
      }

      switch (persistenceKey?.type) {
        case null:
          break;
        case FilePersistorKeyTypes.document:
          // Update the resolver's persistence key for the document.
          _resolver.store.write(docPath, dataStoreName);
          break;
        case FilePersistorKeyTypes.collection:
          // If there is already a document-level persistence key in the resolver tree for this
          // document then it should be removed, since the document is being persisted with a
          // collection-level key.
          _resolver.store.delete(docPath, recursive: false);

          // If the resolved data store for the document's collection has changed, then its data
          // should be grafted from its previous data store to the updated one.
          final collectionDataStore = _index[_resolveStoreName(collectionPath)];
          if (collectionDataStore != dataStore) {
            _resolver.store.write(collectionPath, dataStoreName);

            if (collectionDataStore != null) {
              dataStore.graft(collectionDataStore, collectionPath);
            }
          }
          break;
      }

      await dataStore.writePath(docPath, docData, encrypted);
    }

    await _sync();
  }

  Future<void> clear(List<String> paths) async {
    await Future.wait(paths.map(_clear).toList());
    await _sync();
  }

  Future<void> clearAll() async {
    await Future.wait([
      ..._index.values.map((dataStore) => dataStore.delete()),
      _resolver.delete(),
    ]);

    _index.clear();
  }
}
