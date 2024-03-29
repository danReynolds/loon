import 'dart:io';
import 'dart:isolate';
import 'package:loon/loon.dart';
import 'package:loon/persistor/file_persistor/file_data_store.dart';
import 'package:loon/persistor/file_persistor/messages.dart';
import 'package:loon/utils.dart';
import 'package:path/path.dart' as path;

typedef DocumentDataStore = Map<String, Map<String, FileDataStore>>;

class FilePersistorWorker {
  /// The persistor's send port.
  final SendPort sendPort;

  /// This worker's receive port.
  final receivePort = ReceivePort();

  /// An index of file data stores by name.
  final Map<String, FileDataStore> _fileDataStoreIndex = {};

  /// An index of a documents by collection to the file data store that the document is persisted in.
  final DocumentDataStore _documentDataStoreIndex = {};

  final FileDataStoreFactory factory;

  FilePersistorWorker._({
    required this.sendPort,
    required this.factory,
  });

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

  Future<T> _measureOperation<T>(String label, Future<T> Function() operation) {
    return measureDuration(
      label,
      operation,
      output: _sendDebugResponse,
    );
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
  /// Message request handlers
  ///

  void _init(InitMessageRequest request) {
    // Start listening to messages from the persistor on the worker's receive port.
    receivePort.listen(_onMessage);
    // Send a successful message response containing the worker's send port.
    _sendMessageResponse(request.success(receivePort.sendPort));
  }

  void _hydrate(HydrateMessageRequest request) {
    _measureOperation('Hydration operation', () async {
      try {
        final SerializedCollectionStore collectionStore = {};

        final files = factory.directory
            .listSync()
            .whereType<File>()
            .where(
                (file) => factory.fileRegex.hasMatch(path.basename(file.path)))
            .toList();

        // Attempt to hydrate the file data stores. If any are corrupt, they are returned as null and omitted
        // from the document hydration.
        final hydratedDataStores = await Future.wait(
          files.map((file) => factory.fromFile(file)).map((dataStore) async {
            try {
              await dataStore.hydrate();
              return dataStore;
            } catch (e) {
              _sendDebugResponse(
                'Error hydrating collection: ${dataStore.name}',
              );
              return null;
            }
          }),
        );
        final fileDataStores = hydratedDataStores.whereType<FileDataStore>();

        // On hydration, the following actions must be performed for each file data store:
        // 1. The data store should be added to the data store index.
        // 2. Each of the data store's documents should be indexed into the document data store index by its collection and ID.
        // 3. Each of the data store's documents should be grouped into the collection data store by collection.
        for (final fileDataStore in fileDataStores) {
          _fileDataStoreIndex[fileDataStore.name] = fileDataStore;

          for (final documentDataEntry in fileDataStore.data.entries) {
            final documentKey = documentDataEntry.key;
            final [collection, documentId] = documentKey.split(':');

            final documentDataStore =
                _documentDataStoreIndex[collection] ??= {};
            documentDataStore[documentId] = fileDataStore;

            final documentCollectionStore = collectionStore[collection] ??= {};
            documentCollectionStore[documentId] = documentDataEntry.value;
          }
        }

        _sendMessageResponse(request.success(collectionStore));
      } catch (e) {
        _sendMessageResponse(request.error('Hydration error'));
      }
    });
  }

  void _persist(PersistMessageRequest request) {
    try {
      _measureOperation('Persist operation', () async {
        for (final doc in request.data) {
          final documentKey = doc.key;
          final [collection, documentId] = documentKey.split(':');
          final docJson = doc.data;
          final documentDataStoreName = doc.dataStoreName;
          final documentDataStore =
              _fileDataStoreIndex[documentDataStoreName] ??=
                  factory.fromDoc(doc);

          // If the document has changed the file data store it should be stored in, then it should
          // be removed from its previous file data store (if one exists) and placed in the new one.
          final prevDocumentDataStore =
              _documentDataStoreIndex[collection]?[documentId];
          if (prevDocumentDataStore != null &&
              documentDataStore != prevDocumentDataStore) {
            prevDocumentDataStore.removeDocument(documentKey);
          }

          if (docJson != null) {
            documentDataStore.updateDocument(documentKey, docJson);
            _documentDataStoreIndex[collection] ??= {};
            _documentDataStoreIndex[collection]![documentId] =
                documentDataStore;
          } else {
            documentDataStore.removeDocument(documentKey);
            _documentDataStoreIndex[collection]?.remove(documentKey);
          }
        }

        await _sync();

        _sendMessageResponse(request.success());
      });
    } catch (e) {
      _sendMessageResponse(request.error('Persist failed'));
    }
  }

  void _clear(ClearMessageRequest request) {
    final collection = request.collection;

    _measureOperation('Clear operation', () async {
      try {
        for (final collectionEntry
            in _documentDataStoreIndex.entries.toList()) {
          final collectionName = collectionEntry.key;
          final documentDataStoreIndex = collectionEntry.value;

          // Delete all documents from the cleared collection and its subcollections.
          if (collectionName == collection ||
              collectionName.startsWith('${collection}__')) {
            for (final docEntry in documentDataStoreIndex.entries) {
              final documentId = docEntry.key;
              final documentDataStore = docEntry.value;

              documentDataStore.removeDocument('$collectionName:$documentId');
            }

            _documentDataStoreIndex.remove(collection);
          }
        }

        await _sync();

        _sendMessageResponse(request.success());
      } catch (e) {
        _sendMessageResponse(
          request.error('Clear ${request.collection} failed'),
        );
      }
    });
  }

  void _clearAll(ClearAllMessageRequest request) {
    _measureOperation('ClearAll operation', () async {
      try {
        _fileDataStoreIndex.clear();
        _documentDataStoreIndex.clear();
        await Future.wait(
          _fileDataStoreIndex.values.map((dataStore) => dataStore.delete()),
        );

        _sendMessageResponse(request.success());
      } catch (e) {
        _sendMessageResponse(request.error('ClearAll failed'));
      }
    });
  }
}
