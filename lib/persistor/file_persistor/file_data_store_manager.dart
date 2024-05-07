import 'dart:io';
import 'package:encrypt/encrypt.dart';
import 'package:loon/loon.dart';
import 'package:loon/persistor/file_persistor/file_data_store.dart';
import 'package:loon/persistor/file_persistor/file_persist_document.dart';
import 'package:loon/persistor/file_persistor/file_persistor_settings.dart';

class FileDataStoreManager {
  final Encrypter? encrypter;

  /// The directory in which a file data store is persisted.
  final Directory directory;

  /// The meta file data store.
  late final MetaFileDataStore _meta;

  /// The index of [FileDataStore] objects by name.
  final Map<String, FileDataStore> _index = {};

  /// The index of document paths to the [FileDataStore] object in which the document currently is stored.
  final IndexedValueStore<FileDataStore> _documentIndex = IndexedValueStore();

  FileDataStoreManager({
    required this.directory,
    this.encrypter,
  });

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
      Future.sync(() {
        if (_index.isEmpty) {
          return _meta.delete();
        }
        return _meta.persist();
      })
    ]);
  }

  /// Clears the provided path and all of its subpaths from each data store that contains
  /// data under that path.
  Future<void> _clear(String path) async {
    final stores = _index.values.where((store) => store.hasEntry(path));

    // Unhydrated stores containing the path must be hydrated before the data can be removed.
    final unhydratedStores = stores.where((store) => !store.isHydrated);
    if (unhydratedStores.isNotEmpty) {
      await Future.wait(unhydratedStores.map((store) => store.hydrate()));
    }

    for (final store in stores) {
      store.removeEntry(path);
    }

    _documentIndex.delete(path);
  }

  Future<void> init() async {
    _meta = MetaFileDataStore(
      index: _index,
      directory: directory,
      encrypter: encrypter,
    );

    // Immediately hydrate the meta data store, since the [FileDataStore] meta data is required
    // for processing subsequent data store hydrate/persist operations.
    await _meta.hydrate();
  }

  /// Hydrates the given paths and returns a map of document paths to their serialized data.
  Future<Map<String, Json>> hydrate(List<String>? paths) async {
    final Set<FileDataStore> dataStores = {};

    // If the hydration operation is only for certain paths, then resolve all of the file data stores
    // relevant to the given paths and their subpaths and hydrate those data stores.
    if (paths != null) {
      for (final path in paths) {
        dataStores.addAll(_index.values.where((store) => store.hasEntry(path)));
      }
    } else {
      // If no specific collections have been specified, then hydrate all file data stores.
      dataStores.addAll(_index.values);
    }

    await Future.wait(dataStores.map((store) => store.hydrate()));

    final Map<String, Json> data = {};
    for (final dataStore in dataStores) {
      final extractedData = dataStore.extractValues();

      for (final docPath in extractedData.keys) {
        // In the unlikely scenario where a hydrated document already exists in a different data store,
        // then it must have been written with an updated persistence key and value before it was hydrated
        // from this data store. In that case, this hydrated value is stale and should be deleted from both
        // the data store and the extracted data.
        final existingDataStore = _documentIndex.get(docPath);
        if (existingDataStore != null && existingDataStore != dataStore) {
          extractedData.remove(docPath);
          dataStore.removeEntry(docPath);
        } else {
          // Otherwise write the hydrated document path to the index.
          // TODO: Figure this out. It shouldn't just write the doc to the index, since
          // the doc may not have its own persistence key and was put in this store because of a parent key.
          // Use a separate hydration index to compare?
          _documentIndex.write(docPath, dataStore);
        }
      }

      data.addAll(extractedData);
    }

    return data;
  }

  Future<void> persist(List<FilePersistDocument> docs) async {
    if (docs.isEmpty) {
      return;
    }

    for (final doc in docs) {
      final docPath = doc.path;
      final collectionPath = doc.parent;
      final docData = doc.data;
      final persistenceKey = doc.key;
      final encryptionEnabled = doc.encryptionEnabled;

      // If the document has been deleted, then clear it and its subcollections from the store.
      if (docData == null) {
        await _clear(docPath);
        continue;
      }

      FileDataStore dataStore;

      if (persistenceKey != null) {
        final path = switch (persistenceKey.type) {
          FilePersistorKeyTypes.collection => collectionPath,
          FilePersistorKeyTypes.document => docPath,
        };

        final prevDataStore = _documentIndex.getNearest(path);
        final dataStoreName = persistenceKey.value;

        dataStore = _index[dataStoreName] ??= FileDataStore.create(
          dataStoreName,
          encrypter: encrypter,
          encrypted: encryptionEnabled,
          directory: directory,
        );

        if (prevDataStore != dataStore) {
          // If the persistence key for the path has changed, then all of the data
          // under that path needs to be moved to the destination data store.
          if (prevDataStore != null) {
            if (!dataStore.isHydrated) {
              await dataStore.hydrate();
            }

            dataStore.graft(prevDataStore, path);
          }

          _documentIndex.write(path, dataStore);
        }
      } else {
        // If the document does not specify a persistence key, then its data store is resolved to the nearest data store
        // found in the document index moving up from its path. If no data store exists in this path yet, then the
        // it defaults to using one named after the document's top-level collection.
        FileDataStore? nearestDataStore = _documentIndex.getNearest(docPath);

        if (nearestDataStore == null) {
          final dataStoreName = docPath.split('__').first;

          dataStore = _index[dataStoreName] ??= FileDataStore.create(
            dataStoreName,
            encrypter: encrypter,
            encrypted: encryptionEnabled,
            directory: directory,
          );

          _documentIndex.write(dataStoreName, dataStore);
        } else {
          dataStore = nearestDataStore;
        }
      }

      // A data store must be hydrated before data can be persisted to it.
      if (!dataStore.isHydrated) {
        await dataStore.hydrate();
      }

      dataStore.writeEntry(docPath, docData);
    }

    await _sync();
  }

  Future<void> clear(String path) async {
    _clear(path);
    await _sync();
  }

  Future<void> clearAll() async {
    await Future.wait([
      ..._index.values.map((dataStore) => dataStore.delete()),
      _meta.delete(),
    ]);

    _index.clear();
    _documentIndex.clear();
  }
}
