import 'dart:async';
import 'dart:convert';
import 'dart:io';
import 'package:loon/logger.dart';
import 'package:path_provider/path_provider.dart';
import 'package:path/path.dart' as path;
import '../../loon.dart';

class FilePersistorSettings<T> extends PersistorSettings<T> {
  /// By default, a document is persisted to a file by its collection name.
  /// If documents in the same collection should be broken into multiple files (due to large collection sizes, etc)
  /// or documents should be grouped together across different collections (due to small collection sizes, etc) then
  /// the persistenc key can be used to group arbitrary documents together into the same persistence file.
  final String? Function(Document doc)? getPersistenceKey;

  FilePersistorSettings({
    this.getPersistenceKey,
    super.persistenceEnabled = true,
  });
}

class FileDataStore {
  final File file;
  final String name;

  /// A map of documents by key (collection:id) to the document's JSON data.
  Map<String, Json> data = {};

  /// Whether the file data store has pending changes that should be persisted.
  bool isDirty = false;

  /// The operation queue ensures that only one operation is ever running against a file data store at a time (hydrate, persist, delete).
  final List<Completer> _operationQueue = [];

  FileDataStore({
    required this.file,
    required this.name,
  });

  void updateDocument(String documentKey, Json? docData) {
    if (docData == null) {
      if (data.containsKey(documentKey)) {
        data.remove(documentKey);
        isDirty = true;
      }
    } else {
      data[documentKey] = docData;
      isDirty = true;
    }
  }

  void removeDocument(String documentKey) {
    if (data.containsKey(documentKey)) {
      data.remove(documentKey);
      isDirty = true;
    }
  }

  Future<String> readFile() {
    return file.readAsString();
  }

  Future<void> writeFile(String value) {
    return file.writeAsString(value);
  }

  Future<void> _runOperation(Future<void> Function() operation) async {
    if (_operationQueue.isNotEmpty) {
      final completer = Completer();
      _operationQueue.add(completer);
      return completer.future;
    }

    try {
      // If the operation fails, then we still move on to the next operation. If it was a persist(),
      // then it can still be recovered, as the file data store will remain marked as dirty and will attempt
      // to be persisted again with the next persistence operation.
      await operation();
    } finally {
      // Start the next operation after the previous one completes.
      if (_operationQueue.isNotEmpty) {
        final completer = _operationQueue.removeAt(0);
        completer.complete();
      }
    }
  }

  Future<void> delete() {
    return _runOperation(() async {
      if (file.existsSync()) {
        file.deleteSync();
      }
      isDirty = false;
    });
  }

  Future<void> hydrate() async {
    try {
      await _runOperation(() async {
        final Map<String, dynamic> fileJson = jsonDecode(await readFile());
        final hydrationData = fileJson.map(
          (key, dynamic value) => MapEntry(
            key,
            Map<String, dynamic>.from(value),
          ),
        );
        for (final entry in hydrationData.entries) {
          data[entry.key] = entry.value;
        }
      });
    } catch (e) {
      // If hydration fails, then this file data store is corrupt and should be removed from the file data store index.
      printDebug('Corrupt file data store');
      rethrow;
    }
  }

  Future<void> write() {
    return _runOperation(() async {
      if (data.isEmpty) {
        return;
      }

      await writeFile(jsonEncode(data));

      isDirty = false;
    });
  }

  /// Syncs the file data store. Persisting it if it is dirty with data, or deleting
  /// it if dirty with no data. Does nothing if the data store is not dirty.
  Future<void> sync() async {
    if (!isDirty) {
      return;
    }

    if (data.isEmpty) {
      return delete();
    }

    return write();
  }
}

class FileDataStoreFactory {
  final fileRegex = RegExp(r'^loon_(\w+)\.json$');

  /// The global persistor settings.
  final PersistorSettings persistorSettings;

  final Directory directory;

  FileDataStoreFactory({
    required this.directory,
    required this.persistorSettings,
  });

  /// Returns the name of a file data store name for a given document and its persistor settings.
  /// Uses the custom persistence key of the document if specified in its persistor settings,
  /// otherwise it defaults to the document's collection name.
  String getDocumentDataStoreName(Document doc) {
    final documentSettings = doc.persistorSettings ?? persistorSettings;

    if (documentSettings is FilePersistorSettings) {
      return documentSettings.getPersistenceKey?.call(doc) ?? doc.collection;
    }

    return doc.collection;
  }

  FileDataStore fromFile(File file) {
    final match = fileRegex.firstMatch(path.basename(file.path));
    final name = match!.group(1)!;

    return FileDataStore(
      file: file,
      name: name,
    );
  }

  FileDataStore fromDoc(Document doc) {
    final name = getDocumentDataStoreName(doc);

    return FileDataStore(
      name: name,
      file: File("${directory.path}/$name.json"),
    );
  }
}

class FilePersistor extends Persistor {
  /// An index of file data stores by document persistence key.
  final Map<String, FileDataStore> _fileDataStoreIndex = {};

  /// An index of file data stores by collection and document ID.
  final Map<String, Map<String, FileDataStore>> _documentDataStoreIndex = {};

  late final Directory fileDataStoreDirectory;

  late final FileDataStoreFactory factory;

  FilePersistor({
    super.persistenceThrottle = const Duration(milliseconds: 100),
    super.persistorSettings,
    super.onPersist,
  });

  static String getDocumentKey(Document doc) {
    return '${doc.collection}:${doc.id}';
  }

  List<FileDataStore> getFileDataStores() {
    return _fileDataStoreIndex.values.toList();
  }

  Future<void> initStorageDirectory() async {
    final applicationDirectory = await getApplicationDocumentsDirectory();
    fileDataStoreDirectory = Directory('${applicationDirectory.path}/loon');
    await fileDataStoreDirectory.create();
  }

  List<File> _getDataStoreFiles() {
    return fileDataStoreDirectory
        .listSync()
        .whereType<File>()
        .where((file) => factory.fileRegex.hasMatch(path.basename(file.path)))
        .toList();
  }

  @override
  init() async {
    await initStorageDirectory();
    factory = FileDataStoreFactory(
      directory: fileDataStoreDirectory,
      persistorSettings: persistorSettings,
    );
  }

  @override
  persist(docs) async {
    for (final doc in docs) {
      final documentId = doc.id;
      final collection = doc.collection;
      final documentKey = getDocumentKey(doc);
      final documentDataStoreName = factory.getDocumentDataStoreName(doc);
      final documentDataStore =
          _fileDataStoreIndex[documentDataStoreName] ??= factory.fromDoc(doc);

      // If the document has changed the file data store it should be stored in, then it should
      // be removed from its previous file data store (if one exists) and placed in the new one.
      final prevDocumentDataStore =
          _documentDataStoreIndex[collection]?[documentId];
      if (prevDocumentDataStore != null &&
          documentDataStore != prevDocumentDataStore) {
        prevDocumentDataStore.removeDocument(documentKey);
      }

      if (!_documentDataStoreIndex.containsKey(collection)) {
        _documentDataStoreIndex[collection] = {};
      }
      _documentDataStoreIndex[collection]![documentId] = documentDataStore;

      documentDataStore.updateDocument(documentKey, doc.getJson());
    }

    return sync();
  }

  /// Syncs all dirty file data stores, updating and deleting them as necessary.
  Future<void> sync() {
    return Future.wait(
      _fileDataStoreIndex.values.map((dataStore) => dataStore.sync()),
    );
  }

  @override
  hydrate() async {
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

      final documentKeys = fileDataStore.data.keys.toList();
      for (final documentKey in documentKeys) {
        final [collection, documentId] = documentKey.split(':');

        if (!_documentDataStoreIndex.containsKey(collection)) {
          _documentDataStoreIndex[collection] = {};
        }
        _documentDataStoreIndex[collection]![documentId] = fileDataStore;

        if (!collectionStore.containsKey(collection)) {
          collectionStore[collection] = {};
        }

        collectionStore[collection]![documentId] =
            fileDataStore.data[documentKey]!;
      }
    }

    return collectionStore;
  }

  @override
  clear(String collection) async {
    final collectionDataStoreIndex = _documentDataStoreIndex[collection];

    if (collectionDataStoreIndex == null) {
      return;
    }

    _documentDataStoreIndex.remove(collection);

    // Since a custom persistence key can result in documents from the same collection
    // being stored in difference data stores, we need to iterate through the index for the collection
    // and remove the document from its associated data store individually.
    for (final entry in collectionDataStoreIndex.entries) {
      final documentId = entry.key;
      final documentKey = "$collection:$documentId";
      final fileDataStore = entry.value;

      fileDataStore.removeDocument(documentKey);
    }

    // After removing all documents of the collection from their associated data stores,
    // we sync the data stores, re-persisting any that have been updated and still have data
    // and deleting any that are now empty.
    return sync();
  }

  @override
  clearAll() async {
    _fileDataStoreIndex.clear();
    await Future.wait(
      _fileDataStoreIndex.values.map((dataStore) => dataStore.delete()),
    );
  }
}
