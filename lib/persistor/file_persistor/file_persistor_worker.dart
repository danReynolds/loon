import 'dart:io';
import 'dart:isolate';

import 'package:loon/logger.dart';
import 'package:loon/loon.dart';
import 'package:loon/persistor/file_persistor/file_data_store.dart';
import 'package:loon/persistor/file_persistor/file_persistor_task.dart';
import 'package:path/path.dart' as path;

class FilePersistorWorker {
  final PersistorSettings persistorSettings;

  /// The task runner's send port
  final SendPort sendPort;

  /// The worker's receive port
  final receivePort = ReceivePort();

  /// An index of file data stores by name.
  final Map<String, FileDataStore> _fileDataStoreIndex = {};
  final Map<String, FileDataStore> _documentDataStoreIndex = {};

  late final Directory _fileDirectory;
  late final FileDataStoreFactory factory;

  FilePersistorWorker._({
    required this.sendPort,
    required this.persistorSettings,
  });

  static late final FilePersistorWorker instance;

  static init(InitTaskRequest request) {
    instance = FilePersistorWorker._(
      sendPort: request.sendPort,
      persistorSettings: request.persistorSettings,
    );
    instance.onMessage(request);

    instance.receivePort.listen(instance.onMessage);
  }

  _sendTaskResponse(TaskResponse response) {
    sendPort.send(response);
  }

  void onMessage(dynamic message) {
    switch (message) {
      case InitTaskRequest request:
        _init(request);
      case HydrateTaskRequest request:
        _hydrate(request);
      case PersistTaskRequest request:
        _persist(request);
      case ClearTaskRequest request:
        _clear(request);
      default:
        break;
    }
  }

  static String getDocumentKey(Document doc) {
    return '${doc.collection}:${doc.id}';
  }

  List<File> _getDataStoreFiles() {
    return _fileDirectory
        .listSync()
        .whereType<File>()
        .where((file) => factory.fileRegex.hasMatch(path.basename(file.path)))
        .toList();
  }

  /// Syncs all dirty file data stores, updating and deleting them as necessary.
  Future<void> _sync() {
    return Future.wait(
      _fileDataStoreIndex.values.toList().map((dataStore) async {
        if (!dataStore.isDirty) {
          return;
        }

        if (dataStore.data.isEmpty) {
          _fileDataStoreIndex.remove(dataStore.name);
          return dataStore.delete();
        }

        return dataStore.persist();
      }),
    );
  }

  ///
  /// Task request handlers
  ///

  Future<void> _init(InitTaskRequest request) async {
    _fileDirectory = request.directory;

    factory = FileDataStoreFactory(
      directory: _fileDirectory,
      persistorSettings: persistorSettings,
    );

    _sendTaskResponse(
      InitTaskResponse(id: request.id, sendPort: receivePort.sendPort),
    );
  }

  _hydrate(HydrateTaskRequest request) async {
    final SerializedCollectionStore collectionStore = {};

    final files = _getDataStoreFiles();

    // Attempt to hydrate the file data stores. If any are corrupt, they are returned as null and omitted
    // from the document hydration.
    final hydratedDataStores = await Future.wait(
      files.map((file) => factory.fromFile(file)).map((dataStore) async {
        try {
          await dataStore.hydrate();
          return dataStore;
        } catch (e) {
          printDebug('Error hydrating: ${dataStore.name}');
          return null;
        }
      }),
    );
    final fileDataStores = hydratedDataStores.whereType<FileDataStore>();

    // On hydration, the following tasks must be performed for each file data store:
    // 1. The data store should be added to the data store index.
    // 2. Each of the data store's documents should be indexed into the document data store index by its document
    //    index ID.
    // 3. Each of the data store's documents should be grouped into the collection data store by collection.
    for (final fileDataStore in fileDataStores) {
      _fileDataStoreIndex[fileDataStore.name] = fileDataStore;

      for (final dataStoreEntry in fileDataStore.data.entries) {
        final documentKey = dataStoreEntry.key;
        final [collection, documentId] = documentKey.split(':');

        _documentDataStoreIndex[documentKey] = fileDataStore;

        final documentCollectionStore = collectionStore[collection] ??= {};
        documentCollectionStore[documentId] = dataStoreEntry.value;
      }
    }

    _sendTaskResponse(
      HydrateTaskResponse(
        id: request.id,
        data: collectionStore,
      ),
    );
  }

  Future<void> _persist(PersistTaskRequest request) async {
    for (final entry in request.data.entries) {
      final doc = entry.key;
      final json = entry.value;
      final documentKey = getDocumentKey(doc);
      final documentDataStoreName = factory.getDocumentDataStoreName(doc);
      final documentDataStore =
          _fileDataStoreIndex[documentDataStoreName] ??= factory.fromDoc(doc);

      // If the document has changed the file data store it should be stored in, then it should
      // be removed from its previous file data store (if one exists) and placed in the new one.
      final prevDocumentDataStore = _documentDataStoreIndex[documentKey];
      if (prevDocumentDataStore != null &&
          documentDataStore != prevDocumentDataStore) {
        prevDocumentDataStore.removeDocument(documentKey);
      }

      if (json != null) {
        documentDataStore.updateDocument(documentKey, json);
        _documentDataStoreIndex[documentKey] = documentDataStore;
      } else {
        documentDataStore.removeDocument(documentKey);
        _documentDataStoreIndex.remove(documentKey);
      }
    }

    await _sync();

    _sendTaskResponse(
      PersistTaskResponse(id: request.id),
    );
  }

  _clear(ClearTaskRequest request) async {
    _fileDataStoreIndex.clear();
    _documentDataStoreIndex.clear();
    await Future.wait(
      _fileDataStoreIndex.values.map((dataStore) => dataStore.delete()),
    );

    _sendTaskResponse(ClearTaskResponse(id: request.id));
  }
}
