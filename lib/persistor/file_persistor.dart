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
  late final String collectionPath;
  late final String? shard;
  late Map<String, Json> data;
  bool shouldPersist = false;

  FileDataStore({
    required this.file,
    required this.collectionPath,
    required this.shard,
    Map<String, Json>? data,
  }) {
    this.data = data ?? {};
  }

  static Future<FileDataStore> fromFile(File file) async {
    final json = await jsonDecode(await file.readAsString());

    final meta = json['meta'];
    final Map<String, dynamic> dataJson = json['data'];

    return FileDataStore(
      file: file,
      collectionPath: meta['path'],
      shard: meta['shard'],
      data: dataJson.map(
        (key, dynamic value) => MapEntry(
          key,
          Map<String, dynamic>.from(value),
        ),
      ),
    );
  }

  Future<void> persist() async {
    await file.writeAsString(jsonEncode(toJson()));
  }

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

  Json toJson() {
    return {
      "meta": {
        "path": collectionPath,
        "shard": shard,
      },
      "data": data,
    };
  }
}

class FilePersistor extends Persistor {
  Map<String, FileDataStore> _fileDataStoreIndex = {};

  /// An index of which file data store each document is stored in by document ID.
  final Map<String, FileDataStore> _documentFileDataStoreIndex = {};

  late final Directory fileDataStoreDirectory;

  final filenameRegex = RegExp(r'^loon_.*\.json$');

  FilePersistor({
    super.persistorSettings,
  });

  Future<void> _initStorageDirectory() async {
    final applicationDirectory = await getApplicationDocumentsDirectory();
    fileDataStoreDirectory = Directory('${applicationDirectory.path}/loon');
    fileDataStoreDirectory.createSync();
  }

  Future<List<File>> readDataStoreFiles() async {
    return fileDataStoreDirectory.listSync().whereType<File>().where((file) {
      return filenameRegex.hasMatch(path.basename(file.path));
    }).toList();
  }

  Future<List<FileDataStore>> buildFileDataStores() async {
    final files = await readDataStoreFiles();
    return Future.wait(files.map(FileDataStore.fromFile).toList());
  }

  String buildFileDataStoreId({
    required String collectionPath,
    required String? shard,
  }) {
    if (shard != null) {
      return '$collectionPath.$shard';
    }
    return collectionPath;
  }

  FileDataStore buildFileDataStore({
    required String collectionPath,
    required String? shard,
    required PersistorSettings? persistorSettings,
  }) {
    final fileDataStoreId = buildFileDataStoreId(
      collectionPath: collectionPath,
      shard: shard,
    );
    return FileDataStore(
      file: File('${fileDataStoreDirectory.path}/loon_$fileDataStoreId.json'),
      collectionPath: collectionPath,
      shard: shard,
    );
  }

  List<FileDataStore> getFileDataStores() {
    return _fileDataStoreIndex.values.toList();
  }

  @override
  persist(docs) async {
    for (final doc in docs) {
      final collectionPath = doc.path;
      final persistorSettings = doc.persistorSettings ?? this.persistorSettings;

      if (!persistorSettings.persistenceEnabled) {
        continue;
      }

      String? documentDataStoreShard;
      final FileDataStore documentDataStore;

      if (persistorSettings is FilePersistorSettings) {
        final maxShards = persistorSettings.maxShards;

        if (persistorSettings.shardEnabled && maxShards > 1) {
          documentDataStoreShard = persistorSettings.getShard(doc);
          final documentFileDataStoreId = buildFileDataStoreId(
            collectionPath: collectionPath,
            shard: documentDataStoreShard,
          );

          if (!_fileDataStoreIndex.containsKey(documentFileDataStoreId)) {
            final collectionFileDataStores =
                _fileDataStoreIndex.values.where((fileDataStore) {
              return fileDataStore.collectionPath == collectionPath &&
                  fileDataStore.shard != null;
            }).toList();

            if (collectionFileDataStores.length >= maxShards) {
              // If the collection has reached its max shards already, than any additional documents
              // that do not hash to an existing shard are stored in one of them at random.
              final shardIndex = Random().nextInt(maxShards);
              documentDataStoreShard =
                  collectionFileDataStores[shardIndex].shard;
            }
          }
        }
      }

      final documentFileDataStoreId = buildFileDataStoreId(
        collectionPath: collectionPath,
        shard: documentDataStoreShard,
      );

      if (_fileDataStoreIndex.containsKey(documentFileDataStoreId)) {
        documentDataStore = _fileDataStoreIndex[documentFileDataStoreId]!;
      } else {
        documentDataStore =
            _fileDataStoreIndex[documentFileDataStoreId] = buildFileDataStore(
          collectionPath: collectionPath,
          shard: documentDataStoreShard,
          persistorSettings: persistorSettings,
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
      fileDataStoresToPersist.map((dataStore) => dataStore.persist()).toList(),
    );
  }

  @override
  hydrate() async {
    await _initStorageDirectory();
    final fileDataStores = await buildFileDataStores();

    for (final fileDataStore in fileDataStores) {
      final documentIds = fileDataStore.data.keys.toList();
      for (final documentId in documentIds) {
        _documentFileDataStoreIndex[documentId] = fileDataStore;
      }
    }

    _fileDataStoreIndex = fileDataStores.fold({}, (acc, store) {
      final storeId = buildFileDataStoreId(
        collectionPath: store.collectionPath,
        shard: store.shard,
      );

      return {
        ...acc,
        storeId: store,
      };
    });

    return fileDataStores.fold<SerializedCollectionStore>(
      {},
      (acc, fileDataStore) {
        final existingCollectionData = acc[fileDataStore.collectionPath];
        final fileDataStoreCollectionData = fileDataStore.data;

        // Multiple file data stores can map to the same collection in the case of sharded stores.
        if (existingCollectionData != null) {
          return {
            ...acc,
            fileDataStore.collectionPath: {
              ...existingCollectionData,
              ...fileDataStoreCollectionData,
            }
          };
        }
        return {
          ...acc,
          fileDataStore.collectionPath: fileDataStoreCollectionData,
        };
      },
    );
  }

  @override
  clear(String collection) async {
    final collectionDataStores = _fileDataStoreIndex.values
        .where((fileDataStore) => fileDataStore.collectionPath == collection)
        .toSet();

    await Future.wait(
      collectionDataStores.map(
        (dataStore) async {
          await dataStore.file.delete();
          _fileDataStoreIndex.remove(
            buildFileDataStoreId(
              collectionPath: dataStore.collectionPath,
              shard: dataStore.shard,
            ),
          );
        },
      ),
    );
  }

  @override
  clearAll() {
    return Future.wait(
      _fileDataStoreIndex.values
          .map(
            (collectionDataStore) => clear(collectionDataStore.collectionPath),
          )
          .toList(),
    );
  }
}
