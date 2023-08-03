import 'dart:convert';
import 'dart:io';
import 'dart:math';

import 'package:path_provider/path_provider.dart';
import 'package:path/path.dart' as path;

import '../loon.dart';

class FilePersistorSettings<T> extends PersistorSettings<T> {
  final String? Function(Document<T> doc)? shardFn;
  final int maxShards;

  bool get shardEnabled {
    return shardFn != null;
  }

  String? getShard(Document doc) {
    if (shardFn == null) {
      return null;
    }

    return shardFn!(doc as Document<T>);
  }

  FilePersistorSettings({
    super.persistenceEnabled = true,
    this.shardFn,
    this.maxShards = 1,
  });
}

class FileDataStore {
  final File file;
  final String collection;
  final String? shard;

  Map<String, Json> data = {};
  bool shouldPersist = false;
  bool isDeleting = false;

  FileDataStore({
    required this.file,
    required this.collection,
    required this.shard,
  });

  void updateDocument(BroadcastDocument doc) {
    final docId = doc.id;
    final docData = doc.getJson();

    if (docData == null) {
      if (data.containsKey(docId)) {
        data.remove(docId);
      }
    } else {
      data[docId] = docData;
    }

    if (!shouldPersist) {
      shouldPersist = true;
    }
  }

  void removeDocument(String docId) {
    if (data.containsKey(docId)) {
      data.remove(docId);

      if (!shouldPersist) {
        shouldPersist = true;
      }
    }
  }

  Future<String> readFile() {
    return file.readAsString();
  }

  Future<void> writeFile(String value) async {
    await file.writeAsString(value);
  }

  Future<void> delete() async {
    data = {};
    await file.delete();
  }

  Future<void> hydrate() async {
    if (!file.existsSync()) {
      return;
    }

    final Map<String, dynamic> fileJson = jsonDecode(await readFile());
    data = fileJson.map(
      (key, dynamic value) => MapEntry(
        key,
        Map<String, dynamic>.from(value),
      ),
    );
  }

  Future<void> persist() async {
    await writeFile(jsonEncode(data));
    shouldPersist = false;
  }

  String get filename {
    return path.basename(file.path);
  }
}

class FilePersistor extends Persistor {
  /// An index of [FileDataStore] entries by the data store collection name.
  Map<String, FileDataStore> _fileDataStoreIndex = {};

  /// An index of which file data store each document is stored in by document ID.
  final Map<String, FileDataStore> _documentFileDataStoreIndex = {};

  late final Directory fileDataStoreDirectory;

  final filenameRegex = RegExp(r'^loon_(\w+)(?:\.(shard_\w+))?\.json$');

  FilePersistor({
    super.persistorSettings,
  });

  Future<void> _initStorageDirectory() async {
    final applicationDirectory = await getApplicationDocumentsDirectory();
    fileDataStoreDirectory = Directory('${applicationDirectory.path}/loon');
    await fileDataStoreDirectory.create();
  }

  Future<List<File>> _readDataStoreFiles() async {
    return fileDataStoreDirectory
        .listSync()
        .whereType<File>()
        .where((file) => filenameRegex.hasMatch(path.basename(file.path)))
        .toList();
  }

  String buildFileDataStoreFilename({
    required String collection,
    required String? shard,
    required PersistorSettings? settings,
  }) {
    final collectionFilename = 'loon_$collection';

    if (shard != null) {
      return '$collectionFilename.shard_$shard.json';
    }
    return '$collectionFilename.json';
  }

  FileDataStore buildFileDataStore({
    required String collection,
    required PersistorSettings? settings,
    required String? shard,
  }) {
    final filename = buildFileDataStoreFilename(
      collection: collection,
      shard: shard,
      settings: settings,
    );
    return FileDataStore(
      file: File("${fileDataStoreDirectory.path}/$filename"),
      collection: collection,
      shard: shard,
    );
  }

  FileDataStore parseFileDataStore({required File file}) {
    final match = filenameRegex.firstMatch(path.basename(file.path))!;
    final collection = match.group(1)!;
    final shard = match.group(2);

    return buildFileDataStore(
      collection: collection,
      shard: shard,
      settings: null,
    );
  }

  List<FileDataStore> getFileDataStores() {
    return _fileDataStoreIndex.values.toList();
  }

  @override
  persist(docs) async {
    for (final doc in docs) {
      final collection = doc.collection;
      final persistorSettings = doc.persistorSettings ?? this.persistorSettings;

      if (persistorSettings is! FilePersistorSettings ||
          !persistorSettings.persistenceEnabled) {
        continue;
      }

      String? documentDataStoreShard;
      final FileDataStore documentDataStore;
      final String documentDataStoreFilename;

      final maxShards = persistorSettings.maxShards;

      if (persistorSettings.shardEnabled && maxShards > 1) {
        documentDataStoreShard = persistorSettings.getShard(doc);
        final documentDataStoreShardFilename = buildFileDataStoreFilename(
          collection: collection,
          shard: documentDataStoreShard,
          settings: persistorSettings,
        );

        if (!_fileDataStoreIndex.containsKey(documentDataStoreShardFilename)) {
          final collectionFileDataStores =
              _fileDataStoreIndex.values.where((fileDataStore) {
            return fileDataStore.collection == collection;
          }).toList();

          if (collectionFileDataStores.length >= maxShards) {
            // If the collection has reached its max shards already, then any additional documents
            // that do not hash to an existing shard are stored in one of them at random.
            final shardIndex = Random().nextInt(maxShards);
            documentDataStoreShard = collectionFileDataStores[shardIndex].shard;
          }
        }
      }

      documentDataStoreFilename = buildFileDataStoreFilename(
        collection: collection,
        shard: documentDataStoreShard,
        settings: persistorSettings,
      );

      if (_fileDataStoreIndex.containsKey(documentDataStoreFilename)) {
        documentDataStore = _fileDataStoreIndex[documentDataStoreFilename]!;
      } else {
        documentDataStore =
            _fileDataStoreIndex[documentDataStoreFilename] = buildFileDataStore(
          collection: collection,
          shard: documentDataStoreShard,
          settings: persistorSettings,
        );
      }

      // If the document has changed the file data store it is to be persisted in, it should be removed
      // from its previous data store.
      final prevDocumentDataStore = _documentFileDataStoreIndex[doc.id];
      if (prevDocumentDataStore != null &&
          documentDataStore != prevDocumentDataStore) {
        prevDocumentDataStore.removeDocument(doc.id);
      }

      _documentFileDataStoreIndex[doc.id] = documentDataStore;
      documentDataStore.updateDocument(doc);
    }

    final fileDataStoresToPersist = _fileDataStoreIndex.values
        .where((fileDataStore) => fileDataStore.shouldPersist)
        .toList();

    // If for some reason one or more writes fail, then that is still recoverable as the file data store collections
    // maintains in-memory the latest state of the world, so on next broadcast, any data stores that still
    // require writing will retry at that time.
    await Future.wait(
      fileDataStoresToPersist.map(
        (dataStore) => dataStore.persist(),
      ),
    );
  }

  @override
  hydrate() async {
    await _initStorageDirectory();

    final files = await _readDataStoreFiles();
    final fileDataStores =
        files.map((file) => parseFileDataStore(file: file)).toList();

    await Future.wait(
      fileDataStores.map((dataStore) => dataStore.hydrate()),
    );

    for (final fileDataStore in fileDataStores) {
      final documentIds = fileDataStore.data.keys.toList();

      for (final documentId in documentIds) {
        _documentFileDataStoreIndex[documentId] = fileDataStore;
      }
    }

    _fileDataStoreIndex = fileDataStores.fold({}, (acc, store) {
      return {
        ...acc,
        store.filename: store,
      };
    });

    return fileDataStores.fold<SerializedCollectionStore>(
      {},
      (acc, fileDataStore) {
        final existingCollectionData = acc[fileDataStore.collection];
        final fileDataStoreCollectionData = fileDataStore.data;

        // Multiple data stores map to the same collection across different shards
        // and they should all aggregate their data into a single collection store.
        if (existingCollectionData != null) {
          return {
            ...acc,
            fileDataStore.collection: {
              ...existingCollectionData,
              ...fileDataStoreCollectionData,
            }
          };
        }
        return {
          ...acc,
          fileDataStore.collection: fileDataStoreCollectionData,
        };
      },
    );
  }

  @override
  clear(String collection) async {
    final collectionDataStores = _fileDataStoreIndex.values
        .where((fileDataStore) => fileDataStore.collection == collection)
        .toSet();

    await Future.wait(
      collectionDataStores.map(
        (dataStore) async {
          await dataStore.delete();

          // If new data was added to the data store while the file was being deleted,
          // then do not remove the store from the index.
          if (dataStore.data.isEmpty) {
            _fileDataStoreIndex.remove(dataStore.filename);
          }
        },
      ),
    );
  }

  @override
  clearAll() {
    final clearCollectionFutures = _fileDataStoreIndex.values
        .map((fileDataStore) => fileDataStore.delete())
        .toList();
    return Future.wait(clearCollectionFutures);
  }
}
