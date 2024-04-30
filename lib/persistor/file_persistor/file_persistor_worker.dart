import 'dart:io';
import 'dart:isolate';
import 'package:loon/logger.dart';
import 'package:loon/loon.dart';
import 'package:loon/persistor/file_persistor/file_data_store.dart';
import 'package:loon/persistor/file_persistor/messages.dart';
import 'package:path/path.dart' as path;

/// The reserved name of the [FileDataStore] that indexes collections to the data stores containing their documents.
const _collectionDataStoreKey = '__collection__index__';

class FilePersistorWorker {
  /// The persistor's send port.
  final SendPort sendPort;

  /// This worker's receive port.
  final receivePort = ReceivePort();

  /// The map of relative file data store file names (users.json, etc) to data stores.
  final Map<String, FileDataStore> _fileDataStores = {};

  /// The map of documents to the data store that they currently reside in.
  final _documentDataStoreIndex = IndexedRefValueStore<FileDataStore>();

  final FileDataStoreFactory factory;

  late final Logger logger;

  FilePersistorWorker._({
    required this.sendPort,
    required this.factory,
  }) {
    logger = Logger('Worker', output: _sendDebugResponse);
  }

  FileDataStore<List<String>> get collectionDataStore {
    return _fileDataStores[_collectionDataStoreKey]!
        as FileDataStore<List<String>>;
  }

  static init(InitMessageRequest request) {
    FilePersistorWorker._(
      sendPort: request.sendPort,
      factory: FileDataStoreFactory(
        directory: request.directory,
        encrypter: request.encrypter,
      ),
    )._onMessage(request);
  }

  _sendMessageResponse(MessageResponse response) {
    sendPort.send(response);
  }

  _sendDebugResponse(String text) {
    _sendMessageResponse(DebugMessageResponse(text: text));
  }

  void _onMessage(dynamic message) {
    switch (message) {
      case InitMessageRequest request:
        _init(request);
      case HydrateMessageRequest request:
        _hydrate(request);
      case PersistMessageRequest request:
        _persist(request);
      case ClearMessageRequest request:
        _clear(request);
      case ClearAllMessageRequest request:
        _clearAll(request);
      default:
        break;
    }
  }

  /// Syncs all dirty file data stores, updating and deleting them as necessary.
  Future<void> _sync() {
    return Future.wait(
      _fileDataStores.values.map((dataStore) async {
        if (!dataStore.isDirty) {
          return;
        }

        if (dataStore.isEmpty) {
          _fileDataStores.remove(dataStore);
          return dataStore.delete();
        }

        return dataStore.persist();
      }),
    );
  }

  /// Initializes the data stores, reading them from disk and hydrating the collection index.
  Future<void> _initDataStores() async {
    final files = factory.directory
        .listSync()
        .whereType<File>()
        .where((file) => factory.fileRegex.hasMatch(path.basename(file.path)))
        .toList();

    for (final file in files) {
      final dataStore = factory.fromFile(file);
      _fileDataStores[dataStore.name] = dataStore;
    }

    // If no index store exists, initialize it.
    if (_fileDataStores[_collectionDataStoreKey] == null) {
      _fileDataStores[_collectionDataStoreKey] = FileDataStore(
        file: File("${factory.directory.path}/$_collectionDataStoreKey"),
        name: _collectionDataStoreKey,
      );
    } else {
      // Otherwise immediately hydrate the collection data store, since it is required for subsequent hydrate/persist operations.
      await collectionDataStore.hydrate();
    }
  }

  ///
  /// Message request handlers
  ///

  Future<void> _init(InitMessageRequest request) async {
    await _initDataStores();

    // Start listening to messages from the persistor on the worker's receive port.
    receivePort.listen(_onMessage);

    // Send a successful message response containing the worker's send port.
    _sendMessageResponse(request.success(receivePort.sendPort));
  }

  void _hydrate(HydrateMessageRequest request) {
    logger.measure('Hydration operation', () async {
      try {
        final List<FileDataStore> dataStores = [];

        // If the hydration operation is only for certain collections, then only the file data stores
        // containing documents from those collections and their subcollections are hydrated.
        final collections = request.collections;
        if (collections != null) {
          for (final collection in collections) {
            dataStores.addAll(
              // Extract the file data store names associated with the collection and its subcollections
              // from the collection index data store. This should be performant, as most collections do
              // not have their own data stores and are bundled into their parent's data store, keeping the tree
              // depth small.
              Set.from(collectionDataStore.extractPath(collection.path).values)
                  .map((name) => _fileDataStores[name]!),
            );
          }
          // If no specific collections have been specified, then hydrate all file data stores.
        } else {
          dataStores.addAll(_fileDataStores.values);
        }

        await Future.wait(
          dataStores.map(
            (dataStore) async {
              try {
                await dataStore.hydrate();
                return dataStore;
              } catch (e) {
                logger.log('Error hydrating collection: ${dataStore.name} $e');
                return dataStore;
              }
            },
          ),
        );

        final Map<String, Json> data = {};

        for (final dataStore in dataStores) {
          final data = dataStore.extract();

          // For each document extracted from the data stores, add it to the hydration data
          // and index the document in the data store index.
          for (final entry in data.entries) {
            final docPath = entry.key;
            data[entry.key] = entry.value;
            _documentDataStoreIndex.write(docPath, dataStore);
          }
        }

        _sendMessageResponse(request.success(data));
      } catch (e) {
        _sendMessageResponse(request.error('Hydration error'));
      }
    });
  }

  void _persist(PersistMessageRequest request) {
    logger.measure('Persist operation', () async {
      for (final doc in request.data) {
        final collectionPath = doc.collection;
        final docPath = doc.path;
        final docJson = doc.data;
        final dataStoreName = doc.dataStoreName;

        final prevDocumentDataStore = _documentDataStoreIndex.get(docPath);
        final documentDataStore =
            _fileDataStores[doc.dataStoreName] ??= factory.fromDoc(doc);

        // If this is the first reference to the given file data store for the document's collection,
        // then add the data store to the collection index.
        final dataStoreRefCount =
            _documentDataStoreIndex.getRefCount(docPath, documentDataStore);
        if (dataStoreRefCount == 0) {
          final existingEntry =
              collectionDataStore.getEntry(collectionPath) ?? [];
          collectionDataStore.writeEntry(
            doc.collection,
            [
              ...existingEntry,
              dataStoreName,
            ],
          );
        }

        // If the document has changed the file data store it should be stored in, then it should
        // be removed from its previous file data store (if one exists) and placed in the new one.
        if (documentDataStore != prevDocumentDataStore &&
            prevDocumentDataStore != null) {
          prevDocumentDataStore.removeEntry(docPath);

          final prevDataStoreRefCount = _documentDataStoreIndex.getRefCount(
            docPath,
            prevDocumentDataStore,
          );

          // If this was the last document in the collection referencing this data store, then
          // remove the data store from the collection index.
          if (prevDataStoreRefCount == 1) {
            final existingEntry = collectionDataStore.getEntry(collectionPath);
            if (existingEntry != null) {
              if (existingEntry.length > 1) {
                collectionDataStore.writeEntry(
                  collectionPath,
                  existingEntry..remove(dataStoreName),
                );
              } else {
                collectionDataStore.removeEntry(collectionPath);
              }
            }
          }
        }

        if (docJson != null) {
          documentDataStore.writeEntry(docPath, docJson);
          _documentDataStoreIndex.write(docPath, documentDataStore);
        } else {
          documentDataStore.removeEntry(docPath);
          _documentDataStoreIndex.delete(docPath);
        }
      }

      await _sync();

      _sendMessageResponse(request.success());
    });
  }

  void _clear(ClearMessageRequest request) {
    final collection = request.collection;

    logger.measure('Clear operation', () async {
      // Remove the collection path from the document data store index.
      _documentDataStoreIndex.delete(collection);

      // Aggregate all data stores associated with the collection and its subcollections
      // and remove the collection from each store.
      final dataStores = collectionDataStore
          .extractPath(collection)
          .values
          .expand((e) => e)
          .toSet()
          .map((name) => _fileDataStores[name]!);

      for (final dataStore in dataStores) {
        dataStore.removeEntry(collection);
      }

      await _sync();

      _sendMessageResponse(request.success());
    });
  }

  void _clearAll(ClearAllMessageRequest request) {
    logger.measure('ClearAll operation', () async {
      try {
        final future = Future.wait(
          _fileDataStores.values.map((dataStore) => dataStore.delete()),
        );

        _fileDataStores.clear();
        _documentDataStoreIndex.clear();

        await future;

        _sendMessageResponse(request.success());
      } catch (e) {
        _sendMessageResponse(request.error('ClearAll failed'));
      }
    });
  }
}
