import 'dart:io';
import 'package:encrypt/encrypt.dart';
import 'package:loon/loon.dart';
import 'package:loon/persistor/file_persistor/file_data_store.dart';
import 'package:loon/persistor/file_persistor/file_persist_document.dart';
import 'package:loon/persistor/file_persistor/file_persistor_settings.dart';
import 'package:path/path.dart' as path;

class FileDataStoreManager {
  /// The reserved name of the [FileDataStore] that is used to persist and resolve
  /// the mapping of documents to their corresponding data store.
  static const _resolverKey = '__resolver__';

  final Encrypter? encrypter;

  /// The directory in which a file data store is persisted.
  final Directory directory;

  /// The index of relative file data store file names (users.json, etc) to data stores.
  final Map<String, FileDataStore<Json>> index = {};

  /// The resolver is a separate [FileDataStore] that maps documents to the data stores
  /// in which the documents are stored. It is necessary since the hydration of a particular
  /// collection, for example, needs to know all of the data stores that contain documents
  /// of that collection and its subcollections. The resolver maintains this mapping.
  late final ResolverFileDataStore resolver;

  FileDataStoreManager({
    required this.directory,
    this.encrypter,
  });

  /// Returns the set of [FileDataStore] that contain documents under the given path.
  Set<FileDataStore> _resolve(String path) {
    // Traversing the resolver tree to extract the set of data stores referencing a give path and its subpaths
    // is generally performant, since the number of nodes traversed in the resolver tree scales O(n*m) where n is the number
    // of collections that specify a custom persistence key (small) and m is the number of distinct file data stores (also small).
    return resolver.extractRefs(path).keys.map((name) => index[name]!).toSet();
  }

  /// Syncs all dirty file data stores, updating and deleting them as necessary.
  Future<void> _sync() {
    return Future.wait(
      [
        ...index.values,
        resolver as FileDataStore,
      ].map((dataStore) async {
        if (!dataStore.isDirty) {
          return;
        }

        if (dataStore.isEmpty) {
          index.remove(dataStore);
          return dataStore.delete();
        }

        return dataStore.persist();
      }),
    );
  }

  /// Clears the provided path and all of its subpaths from the data stores that reference
  /// those paths.
  Future<void> _clear(String path) async {
    final stores = _resolve(path);

    for (final store in stores) {
      // Remove the path from each store that had references to data at and under that path.
      store.removeEntry(path);
    }

    // Remove the path from the FileDataStore resolver.
    resolver.removeEntry(path);
  }

  Future<void> init() async {
    resolver = ResolverFileDataStore(
      file: File("${directory.path}/$_resolverKey"),
      name: _resolverKey,
    );

    // Immediately hydrate the resolver, since it is required for any other
    // hydrate/persist operations.
    final resolverFuture = resolver.hydrate();

    final files = directory
        .listSync()
        .whereType<File>()
        .where((file) => fileRegex.hasMatch(path.basename(file.path)))
        .toList();

    for (final file in files) {
      final dataStore = FileDataStore.parse(file, encrypter: encrypter);
      index[dataStore.name] = dataStore;
    }

    await resolverFuture;
  }

  /// Hydrates the given paths and returns a map of document paths to their serialized data.
  Future<Map<String, Json>> hydrate(List<String>? paths) async {
    final List<FileDataStore> dataStores = [];

    // If the hydration operation is only for certain paths, then resolve all of the file data stores
    // relevant to the given paths and their subpaths and hydrate those data stores.
    if (paths != null) {
      for (final path in paths) {
        dataStores.addAll(_resolve(path));
      }
      // If no specific collections have been specified, then hydrate all file data stores.
    } else {
      dataStores.addAll(index.values);
    }

    await Future.wait(
      dataStores.map(
        (dataStore) async {
          try {
            await dataStore.hydrate();
            return dataStore;
          } catch (e) {
            return dataStore;
          }
        },
      ),
    );

    final Map<String, Json> data = {};
    for (final dataStore in dataStores) {
      final data = dataStore.extract();

      for (final entry in data.entries) {
        data[entry.key] = entry.value;
      }
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
        _clear(docPath);
        continue;
      }

      FileDataStore dataStore;

      if (persistenceKey != null) {
        final path = switch (persistenceKey.type) {
          FilePersistorKeyTypes.collection => collectionPath,
          FilePersistorKeyTypes.document => docPath,
        };

        final prevDataStoreName = resolver.getNearestEntry(path);
        final dataStoreName = persistenceKey.value;

        dataStore = index[dataStoreName] ??= FileDataStore.create(
          dataStoreName,
          encrypter: encrypter,
          encryptionEnabled: encryptionEnabled,
          directory: directory,
        );

        // If the persistence key for the path has changed, then all of the data
        // under that path needs to be moved to the destination data store.
        if (prevDataStoreName != null && prevDataStoreName != dataStoreName) {
          final prevDataStore = index[prevDataStoreName];
          if (prevDataStore != null) {
            dataStore.graft(prevDataStore, path);

            // Remove the document itself from the previous data store.
            prevDataStore.removeEntry(docPath);
          }
        }

        // Update the resolver for this path to the new data store.
        resolver.writeEntry(path, dataStoreName);
      } else {
        // If the document does not specify a persistence key, then its data store is resolved to the nearest data store
        // found in the resolver tree moving up from the document path. If no data store exists in this path yet, then the
        // it defaults to using one named after the document's top-level collection.
        String dataStoreName;

        final nearestDataStoreName = resolver.getNearestEntry(docPath);
        if (nearestDataStoreName != null) {
          dataStoreName = nearestDataStoreName;
        } else {
          dataStoreName = docPath.split('__').first;

          // Add the default top-level collection name used for the document's data store to the resolver tree.
          resolver.writeEntry(dataStoreName, dataStoreName);
        }

        dataStore = index[dataStoreName] ??= FileDataStore.create(
          dataStoreName,
          encrypter: encrypter,
          encryptionEnabled: encryptionEnabled,
          directory: directory,
        );
      }

      // Once the document's data store has been determined, it can be written to the resolved store.
      dataStore.writeEntry(docPath, docData);
    }

    await _sync();
  }

  Future<void> clear(String path) async {
    _clear(path);
    await _sync();
  }

  Future<void> clearAll() async {
    await Future.wait(index.values.map((dataStore) => dataStore.delete()));
    await resolver.delete();

    index.clear();
  }
}
