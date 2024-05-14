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

  /// Resolves the set of [FileDataStore] that contain the under and including the given path.
  Set<DualFileDataStore> _resolve(String path) {
    // Resolve the store for the document path itself separately.
    final store = _index[_resolver.store.getNearest(path)];

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

  /// Returns the name of the data store that the given document path resolves to.
  String _resolveDataStoreName(
    String docPath,
    FilePersistorKey? key,
  ) {
    // If a persistence key is specified, then return the data store determined by that key.
    if (key != null) {
      return key.value;
    }

    // If the document does not specify a persistence key, then its data store is resolved to the nearest data store
    // found in the document index moving up from its path. If no data store exists in this path yet, then the
    // it defaults to using one named after the document's top-level collection.
    final nearestDataStoreName = _resolver.store.getNearest(docPath);
    if (nearestDataStoreName != null) {
      return nearestDataStoreName;
    }

    final dataStoreName = docPath.split('__').first;

    // Write the new top-level data store name into the resolver tree.
    _resolver.store.write(dataStoreName, dataStoreName);

    return dataStoreName;
  }

  /// Syncs all file data stores, persisting dirty ones and deleting ones that can now be removed.
  Future<void> _sync() async {
    final dirtyStores =
        _index.values.where((dataStore) => dataStore.isDirty).toList();

    if (dirtyStores.isEmpty) {
      return;
    }

    await Future.wait([
      ...dirtyStores.map((dataStore) async {
        if (dataStore.isEmpty) {
          _index.remove(dataStore.name);
          return dataStore.delete();
        }

        return dataStore.persist();
      }),
      _resolver.persist(),
    ]);
  }

  /// Clears the provided path and all of its subpaths from each data store that contains
  /// data under that path.
  Future<void> _clear(String path) async {
    final stores = _resolve(path);

    await Future.wait(stores.map((store) => store.remove(path)));

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
      _index[dataStore.name] = dataStore;
    }

    // Initialize and immediately hydrate the resolver data, since it is required
    // for processing subsequent data store hydrate/persist operations.
    _resolver = FileDataStoreResolver(directory: directory);
    await _resolver.hydrate();
  }

  /// Hydrates the given paths and returns a map of document paths to their serialized data.
  Future<Map<String, Json>> hydrate(List<String>? paths) async {
    final Set<DualFileDataStore> dataStores = {};

    // If the hydration operation is only for certain paths, then resolve all of the file data stores
    // relevant to the given paths and their subpaths and hydrate those data stores.
    if (paths != null) {
      for (final path in paths) {
        dataStores.addAll(_resolve(path));
      }
    } else {
      // If no specific collections have been specified, then hydrate all file data stores.
      dataStores.addAll(_index.values);
    }

    await Future.wait(dataStores.map((store) => store.hydrate()));

    final Map<String, Json> data = {};
    for (final hydratedStore in dataStores) {
      final (plaintextData, encryptedData) = hydratedStore.extractValues();

      for (final extractedData in [plaintextData, encryptedData]) {
        for (final docPath in extractedData.keys.toList()) {
          // In the situation where a hydrated document is now resolved to a different data store
          // then it was when it was persisted, then there are two scenarios:
          //
          // 1. If the document already exists in the resolved data store, then that means that the
          //    document has been updated since it was persisted and that the hydrated value is stale.
          //    In this scenario, the stale hydrated document should be removed from the extracted hydration data and
          //    removed from its old data store.
          // 2. The document does not exist in the resolved data store, in which case it should be moved from
          //    its old data store to the updated one and delivered in the extracted hydration data.
          final resolvedDataStore = _index[_resolver.store.getNearest(docPath)];
          if (resolvedDataStore != null && resolvedDataStore != hydratedStore) {
            if (resolvedDataStore.has(docPath)) {
              extractedData.remove(docPath);
            } else {
              resolvedDataStore.write(
                docPath,
                extractedData[docPath]!,
                extractedData == encryptedData,
              );
            }
            // In either scenario, the document should be removed from the hydrated data store
            // since it now belongs in the updated resolved data store.
            hydratedStore.remove(docPath, recursive: false);
          }
        }

        data.addAll(extractedData);
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

      final prevDataStore = _index[_resolver.store.getNearest(docPath)];

      // If the persistence key for the document is now null, then remove the previous
      // key for the document (if it exists) ahead of resolving its data store name.
      if (persistenceKey == null) {
        _resolver.store.delete(docPath, recursive: false);
      }

      final dataStoreName = _resolveDataStoreName(docPath, persistenceKey);
      final dataStore = _index[dataStoreName] ??= DualFileDataStore(
        name: dataStoreName,
        encrypter: encrypter,
        directory: directory,
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
          final collectionDataStore =
              _index[_resolver.store.getNearest(collectionPath)];
          if (collectionDataStore != dataStore) {
            _resolver.store.write(collectionPath, dataStoreName);

            if (collectionDataStore != null) {
              dataStore.graft(collectionDataStore, collectionPath);
            }
          }
          break;
      }

      await dataStore.write(docPath, docData, encrypted);
    }

    await _sync();
  }

  Future<void> clear(String path) async {
    await _clear(path);
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
