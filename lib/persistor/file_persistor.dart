import 'dart:async';
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
  File file;
  final String collection;
  final String? shard;

  Map<String, Json> data = {};

  /// Whether the file data store has pending changes that should be persisted.
  bool isDirty = false;

  FileDataStore({
    required this.file,
    required this.collection,
    required this.shard,
  });

  void updateDocument(Document doc) {
    final docId = doc.id;
    final docData = doc.getJson();

    if (docData == null) {
      if (data.containsKey(docId)) {
        data.remove(docId);
        isDirty = true;
      }
    } else {
      data[docId] = docData;
      isDirty = true;
    }
  }

  void removeDocument(String docId) {
    if (data.containsKey(docId)) {
      data.remove(docId);
      isDirty = true;
    }
  }

  Future<String> readFile() {
    return file.readAsString();
  }

  Future<void> writeFile(String value) {
    return file.writeAsString(value);
  }

  Future<void> delete() async {
    if (file.existsSync()) {
      file.deleteSync();
    }
  }

  Future<void> hydrate() async {
    final Map<String, dynamic> fileJson = jsonDecode(await readFile());
    data = fileJson.map(
      (key, dynamic value) => MapEntry(
        key,
        Map<String, dynamic>.from(value),
      ),
    );
  }

  Future<void> persist() async {
    if (data.isEmpty) {
      await delete();
    } else {
      if (!file.existsSync()) {
        file = File(file.path);
      }
      writeFile(jsonEncode(data));
    }

    isDirty = false;
  }

  String get filename {
    return path.basename(file.path);
  }
}

class FilePersistor extends Persistor {
  /// An index of [FileDataStore] entries by the data store collection name.
  Map<String, FileDataStore> _fileDataStoreIndex = {};

  /// An index of which file data store each document is stored in by key Collection:ID.
  final Map<String, FileDataStore> _documentFileDataStoreIndex = {};

  late final Directory fileDataStoreDirectory;

  final _initializedCompleter = Completer<void>();

  final filenameRegex = RegExp(r'^loon_(\w+)(?:\.(shard_\w+))?\.json$');

  FilePersistor({
    super.persistorSettings,
  }) {
    _initStorageDirectory();
  }

  String _getIndexId(String collection, String id) {
    return '$collection:$id';
  }

  Future<void> _initStorageDirectory() async {
    final applicationDirectory = await getApplicationDocumentsDirectory();
    fileDataStoreDirectory = Directory('${applicationDirectory.path}/loon');
    await fileDataStoreDirectory.create();
    _initializedCompleter.complete();
  }

  Future<bool> get isInitialized async {
    await _initializedCompleter.future;
    return true;
  }

  List<File> _readDataStoreFiles() {
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
    await isInitialized;

    for (final doc in docs) {
      final collection = doc.collection;
      final persistorSettings = doc.persistorSettings ?? this.persistorSettings;
      final indexId = _getIndexId(collection, doc.id);

      if (!persistorSettings.persistenceEnabled) {
        continue;
      }

      String? documentDataStoreShard;
      final FileDataStore documentDataStore;
      final String documentDataStoreFilename;

      if (persistorSettings is FilePersistorSettings &&
          persistorSettings.shardEnabled &&
          persistorSettings.maxShards > 1) {
        final maxShards = persistorSettings.maxShards;
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
      final prevDocumentDataStore = _documentFileDataStoreIndex[indexId];
      if (prevDocumentDataStore != null &&
          documentDataStore != prevDocumentDataStore) {
        prevDocumentDataStore.removeDocument(doc.id);
      }

      _documentFileDataStoreIndex[indexId] = documentDataStore;
      documentDataStore.updateDocument(doc);
    }

    final fileDataStoresToPersist = _fileDataStoreIndex.values
        .where((fileDataStore) => fileDataStore.isDirty)
        .toList();

    // If for some reason one or more writes fail, then that is still recoverable as the file data store collections
    // maintains in-memory the latest state of the world, so on next broadcast, any data stores that still
    // require writing will retry at that time.
    await Future.wait(
      fileDataStoresToPersist.map((dataStore) => dataStore.persist()),
    );
  }

  @override
  hydrate() async {
    await isInitialized;

    final files = _readDataStoreFiles();
    final fileDataStores =
        files.map((file) => parseFileDataStore(file: file)).toList();

    await Future.wait(
      fileDataStores.map((dataStore) => dataStore.hydrate()),
    );

    for (final fileDataStore in fileDataStores) {
      final documentIds = fileDataStore.data.keys.toList();

      for (final documentId in documentIds) {
        final indexId = _getIndexId(fileDataStore.collection, documentId);
        _documentFileDataStoreIndex[indexId] = fileDataStore;
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
          _fileDataStoreIndex.remove(dataStore.filename);
        },
      ),
    );
  }

  @override
  clearAll() {
    final clearCollectionFutures = _fileDataStoreIndex.values
        .map((fileDataStore) => fileDataStore.delete())
        .toList();
    _fileDataStoreIndex.clear();
    return Future.wait(clearCollectionFutures);
  }
}
