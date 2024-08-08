import 'dart:async';
import 'dart:io';
import 'package:encrypt/encrypt.dart';
import 'package:loon/loon.dart';
import 'package:loon/persistor/file_persistor/file_data_store.dart';
import 'package:loon/persistor/file_persistor/file_persist_document.dart';
import 'package:loon/persistor/file_persistor/file_persistor_settings.dart';
import 'package:loon/persistor/file_persistor/lock.dart';
import 'package:path/path.dart' as path;

class FileDataStoreManager {
  final Encrypter encrypter;

  /// The directory in which a file data store is persisted.
  final Directory directory;

  /// The duration by which to throttle persistence changes to the file system.
  final Duration persistenceThrottle;

  final FilePersistorSettings settings;

  final void Function() onSync;

  final void Function(String text) onLog;

  /// The resolver that contains a mapping of documents to the file data store in which
  /// the document is currently stored.
  late final FileDataStoreResolver _resolver;

  /// The index of [FileDataStore] objects by name.
  final Map<String, DualFileDataStore> _index = {};

  /// The sync lock is used to block operations from accessing the file system while there is an ongoing sync
  /// operation and conversely blocks a sync from starting until the ongoing operation holding the lock has finished.
  final _syncLock = Lock();

  /// The sync timer is used to throttle syncing changes to the file system using
  /// the given [persistenceThrottle]. After an that mutates the file system operation runs, it schedules
  /// a sync to run on a timer. When the sync runs, it acquires the [_syncLock], blocking any operations
  /// from being processed until the sync completes.
  Timer? _syncTimer;

  late final _logger = Logger('FileDataStoreManager', output: onLog);

  FileDataStoreManager({
    required this.directory,
    required this.encrypter,
    required this.persistenceThrottle,
    required this.onSync,
    required this.onLog,
    required this.settings,
  });

  /// Resolves the data store name for the given path as the nearest value found working up from
  /// the full path, falling back to the default store key if none is found.
  String _resolveStoreName(String path) {
    return _resolver.getNearest(path) ?? FileDataStore.defaultKey;
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
      ..._resolver.extractRefs(path).keys.map((name) => _index[name]!).toSet(),
    };
  }

  void _cancelSync() {
    _syncTimer?.cancel();
    _syncTimer = null;
  }

  void _scheduleSync() {
    _syncTimer ??= Timer(persistenceThrottle, _sync);
  }

  /// Syncs all file data stores to the file system, persisting dirty ones and deleting
  /// ones that can now be removed.
  Future<void> _sync() {
    return _syncLock.run(() {
      return _logger.measure('File Sync', () async {
        final dirtyStores =
            _index.values.where((dataStore) => dataStore.isDirty).toList();

        if (dirtyStores.isEmpty) {
          return;
        }

        await Future.wait([
          ...dirtyStores.map((store) => store.sync()),
          if (_resolver.isDirty) _resolver.sync(),
        ]);

        for (final store in dirtyStores) {
          if (store.isEmpty) {
            _index.remove(store.name);
          }
        }

        onSync();
        _syncTimer = null;
      });
    });
  }

  /// Clears the provided path and all of its subpaths from each data store that contains
  /// data under that path.
  Future<void> _clear(String path) async {
    final stores = _resolveStores(path);
    await Future.wait(stores.map((store) => store.deletePath(path)));
    _resolver.deletePath(path);
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

    // Initialize the root file data store if it does not exist yet.
    if (!_index.containsKey(FileDataStore.defaultKey)) {
      _index[FileDataStore.defaultKey] = DualFileDataStore(
        name: FileDataStore.defaultKey,
        directory: directory,
        encrypter: encrypter,
        isHydrated: true,
      );
    }

    // Initialize and immediately hydrate the resolver data, since it is required
    // for processing subsequent data store hydrate/persist operations.
    _resolver = FileDataStoreResolver(directory: directory);
    await _resolver.hydrate();
  }

  /// Hydrates the given paths and returns a map of document paths to their serialized data.
  Future<Map<String, dynamic>> hydrate(List<String>? paths) {
    return _syncLock.run(
      () async {
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

        final Map<String, dynamic> data = {};
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
              final (plaintextData, encryptedData) =
                  dataStore.extractValues(path);
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
      },
    );
  }

  Future<void> persist(
    /// A map of paths in the store to the [FileDataStore] key in which documents
    /// under the given path should be stored.
    Map<String, String?> keys,

    /// The list of updated documents to persist.
    List<FilePersistDocument> docs,
  ) {
    return _syncLock.run(() async {
      // First process the persistor keys associated with the updated documents, moving
      // data that has changed stores and updating resolver paths with the updated keys.
      for (final entry in keys.entries) {
        final path = entry.key;
        final prevDataStoreName = _resolveStoreName(path);
        final dataStoreName = entry.value;

        if (prevDataStoreName != dataStoreName) {
          final prevDataStore = _index[prevDataStoreName];
          final defaultedDataStoreName =
              entry.value ?? FileDataStore.defaultKey;
          final dataStore =
              _index[defaultedDataStoreName] ??= DualFileDataStore(
            name: defaultedDataStoreName,
            encrypter: encrypter,
            directory: directory,
            isHydrated: true,
          );

          // If the resolved data store for the persistence path has changed, then its data
          // should be grafted from its previous data store to the updated one.
          if (prevDataStore != null) {
            dataStore.graft(prevDataStore, path);
          }

          if (dataStoreName != null) {
            _resolver.writePath(path, dataStoreName);
          } else {
            _resolver.deletePath(path, recursive: false);
          }
        }
      }

      // After updating the resolved data stores for document paths, iterate through the updated
      // documents and
      for (final doc in docs) {
        final docPath = doc.path;
        final docData = doc.data;
        final encrypted = doc.encrypted;

        // If the document has been deleted, then clear it and its subcollections from the store.
        if (docData == null) {
          await _clear(docPath);
          // Otherwise, write its associated data store with the updated document data.
        } else {
          final dataStore = _index[_resolveStoreName(docPath)]!;
          await dataStore.writePath(docPath, docData, encrypted);
        }
      }

      _scheduleSync();
    });
  }

  Future<void> clear(List<String> paths) {
    return _syncLock.run(() async {
      await Future.wait(paths.map(_clear).toList());
      _scheduleSync();
    });
  }

  Future<void> clearAll() {
    return _syncLock.run(() async {
      // Cancel any pending sync, since all data stores are being cleared immediately.
      _cancelSync();

      await Future.wait([
        ..._index.values.map((dataStore) => dataStore.delete()),
        _resolver.delete(),
      ]);

      _index.clear();
    });
  }
}
