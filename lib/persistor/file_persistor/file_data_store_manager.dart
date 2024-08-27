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
            _index.values.where((dataStore) => dataStore.isDirty);

        if (dirtyStores.isEmpty) {
          return;
        }

        await Future.wait([
          ...dirtyStores.map((store) => store.sync()),
          if (_resolver.isDirty) _resolver.sync(),
        ]);

        for (final store in dirtyStores.toList()) {
          if (store.isEmpty) {
            _index.remove(store.name);
          }
        }

        onSync();
        _syncTimer = null;
      });
    });
  }

  /// Returns a list of all data stores that contain documents at/under the given path.
  /// These data stores include:
  ///
  /// 1. The nearest data store for the resolver path going up the resolver tree.
  /// 2. The set of data stores that exist in the subtree of the resolver under the given path.
  List<DualFileDataStore> _resolveDataStores(String path) {
    final List<String> dataStoreNames = [];

    // 1.
    final nearestDataStoreName = _resolver.getNearest(path)?.$2;
    if (nearestDataStoreName != null) {
      dataStoreNames.add(nearestDataStoreName);
    }

    // 2.
    dataStoreNames.addAll(_resolver.extractValues(path));

    return dataStoreNames
        .map((dataStoreName) => _index[dataStoreName])
        .whereType<DualFileDataStore>()
        .toList();
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
  Future<Map<String, dynamic>> hydrate(List<String>? paths) {
    return _syncLock.run(
      () async {
        final Map<String, List<DualFileDataStore>> pathDataStores = {};
        final Set<DualFileDataStore> dataStores = {};

        // If the hydration operation is only for certain paths, then resolve all of the file data stores
        // reachable under the given paths and hydrate only those data stores.
        if (paths != null) {
          for (final path in paths) {
            final stores = pathDataStores[path] = _resolveDataStores(path);
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
            // Only extract the data in the hydrated store that falls under the requested store path. This ensures that
            // only the data that was requested is hydrated and limits the data copied over to the main isolate to only what is necessary.
            //
            // If later on the client requests to hydrate a path for a data store that has already been
            // hydrated but has not yet delivered the data under that path to the client, then this still
            // works as expected, as the hydration operation will just extract that data from the already hydrated
            // data store and return it.
            for (final dataStore in pathDataStores[path]!) {
              data.addAll(dataStore.extract(path));
            }
          }
        } else {
          for (final dataStore in _index.values) {
            data.addAll(dataStore.extract());
          }
        }

        return data;
      },
    );
  }

  Future<void> persist(
    /// A local persistence key resolver derived from the set of updated documents.
    ValueStore<String> localResolver,

    /// The list of updated documents to persist.
    List<FilePersistDocument> docs,
  ) {
    return _syncLock.run(() async {
      Set<DualFileDataStore> dataStores = {};
      Map<String, List<DualFileDataStore>> pathDataStores = {};

      // Pre-calculate and hydrate all resolved file data stores relevant to the updated documents.
      for (final doc in docs) {
        final docPath = doc.path;
        final docData = doc.data;

        if (docData == null) {
          final stores = pathDataStores[docPath] = _resolveDataStores(docPath);
          dataStores.addAll(stores);
        } else {
          final prevDataStoreName = _resolver.getNearest(docPath)!.$2;
          final nextDataStoreName = localResolver.getNearest(docPath)!.$2;
          final prevDataStore = _index[prevDataStoreName] ??= DualFileDataStore(
            name: prevDataStoreName,
            encrypter: encrypter,
            directory: directory,
            isHydrated: true,
          );
          final nextDataStore = _index[nextDataStoreName] ??= DualFileDataStore(
            name: nextDataStoreName,
            encrypter: encrypter,
            directory: directory,
            isHydrated: true,
          );
          dataStores.add(prevDataStore);
          dataStores.add(nextDataStore);
        }
      }

      await Future.wait(dataStores.map((dataStore) => dataStore.hydrate()));

      for (final doc in docs) {
        final docPath = doc.path;
        final docData = doc.data;
        final encrypted = doc.encrypted;

        // If the document has been deleted, then clear its data recursively from each of its
        // resolved data stores.
        if (docData == null) {
          _resolver.deletePath(docPath);
          for (final dataStore in pathDataStores[docPath]!) {
            dataStore.recursiveDelete(docPath);
          }
          // Otherwise, write its associated data store with the updated document data.
        } else {
          final prevResult = _resolver.getNearest(docPath)!;
          final prevResolverPath = prevResult.$1;
          final prevResolverValue = prevResult.$2;

          final nextResult = localResolver.getNearest(docPath)!;
          final nextResolverPath = nextResult.$1;
          final nextResolverValue = nextResult.$2;

          final prevDataStoreName = prevResolverValue;
          final prevDataStore = _index[prevDataStoreName]!;

          final dataStoreName = nextResolverValue;
          final dataStore = _index[dataStoreName]!;

          _resolver.writePath(nextResolverPath, nextResolverValue);

          // Scenario 1: A document's resolver value changes and its path stays the same.
          //
          // When a document is written with the same resolver path a__b__c and updated resolver value 2 from 1,
          // then store 1 grafts *all* its data under resolver path a__b__c into store 2 at resolver path a__b__c.
          if (nextResolverValue != prevResolverValue &&
              nextResolverPath == prevResolverPath) {
            dataStore.graft(
              nextResolverPath,
              prevResolverPath,
              null,
              prevDataStore,
            );
          }
          // Scenario 2: A document's resolver path changes from a shorter path to a longer path.
          //
          // When a document is updated from previous resolver path a__b__c to descendant resolver path a__b__c__d,
          // then data under path a__b__c__d in resolver path a__b__c of the previous store should be grafted into resolver path a__b__c__d of the next store.
          //
          if (nextResolverPath.length > prevResolverPath.length) {
            dataStore.graft(
              nextResolverPath,
              prevResolverPath,
              nextResolverPath,
              prevDataStore,
            );
          }
          // Scenario 3: A document's resolver path changes from a longer path to a shorter path.
          //
          // When a document is updated from previous resolver path a__b__c__d to resolver path a__b__c,
          // then *all* data in resolver path a__b__c__d of the previous store should be grafted into the next store with resolver path a__b__c.
          if (nextResolverPath.length < prevResolverPath.length) {
            _resolver.deletePath(prevResolverPath, recursive: false);
            dataStore.graft(
              nextResolverPath,
              prevResolverPath,
              null,
              prevDataStore,
            );
          }

          dataStore.writePath(
            nextResolverPath,
            docPath,
            docData,
            encrypted,
          );
        }
      }

      _scheduleSync();
    });
  }

  Future<void> clear(List<String> paths) {
    return _syncLock.run(() async {
      Set<DualFileDataStore> dataStores = {};
      Map<String, List<DualFileDataStore>> pathDataStores = {};

      for (final path in paths) {
        final stores = pathDataStores[path] = _resolveDataStores(path);
        dataStores.addAll(stores);
      }

      if (dataStores.isEmpty) {
        return;
      }

      await Future.wait(dataStores.map((dataStore) => dataStore.hydrate()));

      for (final path in paths) {
        for (final dataStore in pathDataStores[path]!) {
          dataStore.recursiveDelete(path);
        }

        _resolver.deletePath(path);
      }

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
