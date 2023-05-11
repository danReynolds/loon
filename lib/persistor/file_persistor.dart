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
    this.shardFn,
    this.maxShards = 5,
  });
}

class FileDataStore {
  final String collection;
  final String? shard;
  final File file;
  DocumentDataStore data = {};
  bool shouldPersist = false;

  FileDataStore({
    required this.collection,
    required this.file,
    this.shard,
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
  }

  Future<String> readFile() {
    return file.readAsString();
  }

  Future<void> writeFile(String value) async {
    await file.writeAsString(value);
  }

  Future<void> delete() async {
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
    shouldPersist = true;
    await writeFile(jsonEncode(data));
    shouldPersist = false;
  }

  String get filename {
    return path.basename(file.path);
  }
}

class FilePersistor extends Persistor {
  Map<String, FileDataStore> _fileDataStoreCollection = {};

  late final Directory _fileDataStoreDirectory;

  final filenameRegex = RegExp(r'loon_(.*?)(?:_(.*?))?\.json');

  Future<void> _initStorageDirectory() async {
    final applicationDirectory = await getApplicationDocumentsDirectory();
    _fileDataStoreDirectory = Directory('${applicationDirectory.path}/loon');
    _fileDataStoreDirectory.createSync();
  }

  Future<List<File>> _readDataStoreFiles() async {
    return _fileDataStoreDirectory
        .listSync()
        .whereType<File>()
        .where((file) => filenameRegex.hasMatch(file.path))
        .toList();
  }

  File _buildFileDataStoreFile({
    required String collection,
    required PersistorSettings? settings,
    String? shard,
  }) {
    final filename = buildFileDataStoreFilename(
      collection: collection,
      shard: shard,
      settings: settings,
    );
    return File('${_fileDataStoreDirectory.path}/$filename');
  }

  FileDataStore buildFileDataStore({required File file}) {
    final match = filenameRegex.firstMatch(file.path)!;
    final collection = match.group(1)!;
    final shard = match.group(2);

    return FileDataStore(
      collection: collection,
      file: file,
      shard: shard,
    );
  }

  String buildFileDataStoreFilename({
    required String collection,
    required PersistorSettings? settings,
    String? shard,
  }) {
    final collectionFilename = 'loon_$collection';

    if (shard != null) {
      return '${collectionFilename}_shard_$shard.json';
    }
    return '$collectionFilename.json';
  }

  List<FileDataStore> getFileDataStores() {
    return _fileDataStoreCollection.values.toList();
  }

  @override
  persist(docs) async {
    final updatedFileDataStores = _fileDataStoreCollection.values
        .where((fileDataStore) => fileDataStore.shouldPersist)
        .toSet();

    for (final doc in docs) {
      final collection = doc.collection;
      final persistorSettings = doc.persistorSettings;

      String? documentDataStoreShard;
      final FileDataStore documentDataStore;
      final String documentDataStoreFilename;

      if (persistorSettings != null &&
          persistorSettings is FilePersistorSettings) {
        final maxShards = persistorSettings.maxShards;

        if (persistorSettings.shardEnabled && maxShards > 1) {
          documentDataStoreShard = persistorSettings.getShard(doc);
          final documentDataStoreShardFilename = buildFileDataStoreFilename(
            collection: collection,
            shard: documentDataStoreShard,
            settings: persistorSettings,
          );

          if (!_fileDataStoreCollection
              .containsKey(documentDataStoreShardFilename)) {
            final collectionFileDataStores =
                _fileDataStoreCollection.values.where((fileDataStore) {
              return fileDataStore.collection == collection &&
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

      documentDataStoreFilename = buildFileDataStoreFilename(
        collection: collection,
        shard: documentDataStoreShard,
        settings: persistorSettings,
      );

      if (_fileDataStoreCollection.containsKey(documentDataStoreFilename)) {
        documentDataStore =
            _fileDataStoreCollection[documentDataStoreFilename]!;
      } else {
        documentDataStore =
            _fileDataStoreCollection[documentDataStoreFilename] =
                buildFileDataStore(
          file: _buildFileDataStoreFile(
            collection: collection,
            shard: documentDataStoreShard,
            settings: persistorSettings,
          ),
        );
      }

      documentDataStore.updateDocument(doc);

      if (!updatedFileDataStores.contains(documentDataStore)) {
        updatedFileDataStores.add(documentDataStore);
      }
    }

    // If for some reason one or more writes fail, then that is still recoverable as the file data store collections
    // maintains in-memory the latest state of the world, so on next broadcast, any data stores that still
    // require writing will retry at that time.
    await Future.wait(
      updatedFileDataStores.map(
        (dataStore) => dataStore.persist(),
      ),
    );
  }

  @override
  hydrate() async {
    await _initStorageDirectory();

    final files = await _readDataStoreFiles();
    final fileDataStores =
        files.map((file) => buildFileDataStore(file: file)).toList();

    await Future.wait(fileDataStores.map((dataStore) => dataStore.hydrate()));

    _fileDataStoreCollection = fileDataStores.fold({}, (acc, store) {
      return {
        ...acc,
        store.filename: store,
      };
    });

    return fileDataStores.fold({}, (acc, fileDataStore) {
      return {
        fileDataStore.collection: fileDataStore.data,
      };
    });
  }

  @override
  clear(String collection) async {
    final collectionDataStores = _fileDataStoreCollection.values
        .where((fileDataStore) => fileDataStore.collection == collection)
        .toSet();

    await Future.wait(collectionDataStores.map((dataStore) async {
      await dataStore.delete();
      _fileDataStoreCollection.remove(dataStore);
    }));
  }
}
