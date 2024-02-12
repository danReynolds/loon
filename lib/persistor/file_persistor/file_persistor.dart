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
  final Map<String, Json> data = {};

  /// Whether the file data store has pending changes that should be persisted.
  bool isDirty = false;

  FileDataStore({
    required this.file,
    required this.name,
  });

  void updateDocument(String documentKey, Json docData) {
    data[documentKey] = docData;
    isDirty = true;
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

  Future<void> delete() async {
    if (!file.existsSync()) {
      printDebug('Attempted to delete non-existent file');
      return;
    }

    file.deleteSync();
    isDirty = false;
  }

  Future<void> hydrate() async {
    try {
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
    } catch (e) {
      // If hydration fails, then this file data store is corrupt and should be removed from the file data store index.
      printDebug('Corrupt file data store');
      rethrow;
    }
  }

  Future<void> write() async {
    if (data.isEmpty) {
      printDebug('Attempted to write empty data store');
      return;
    }

    await writeFile(jsonEncode(data));

    isDirty = false;
  }
}

class FileDataStoreFactory {
  final fileRegex = RegExp(r'^(\w+)\.json$');

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

  final Map<String, FileDataStore> _documentDataStoreIndex = {};

  late final Directory fileDataStoreDirectory;

  late final FileDataStoreFactory factory;

  FilePersistor({
    super.persistenceThrottle = const Duration(milliseconds: 100),
    super.persistorSettings,
    super.onPersist,
    super.onClear,
    super.onHydrate,
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

      if (doc.exists()) {
        documentDataStore.updateDocument(documentKey, doc.getJson()!);
        _documentDataStoreIndex[documentKey] = documentDataStore;
      } else {
        documentDataStore.removeDocument(documentKey);
        _documentDataStoreIndex.remove(documentKey);
      }
    }

    return sync();
  }

  /// Syncs all dirty file data stores, updating and deleting them as necessary.
  Future<void> sync() {
    return Future.wait(
      _fileDataStoreIndex.values.toList().map((dataStore) async {
        if (!dataStore.isDirty) {
          return;
        }

        if (dataStore.data.isEmpty) {
          _fileDataStoreIndex.remove(dataStore.name);
          return dataStore.delete();
        }

        return dataStore.write();
      }),
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

      for (final dataStoreEntry in fileDataStore.data.entries) {
        final documentKey = dataStoreEntry.key;
        final [collection, documentId] = documentKey.split(':');

        _documentDataStoreIndex[documentKey] = fileDataStore;

        final documentCollectionStore = collectionStore[collection] ??= {};
        documentCollectionStore[documentId] = dataStoreEntry.value;
      }
    }

    return collectionStore;
  }

  @override
  clear() async {
    _fileDataStoreIndex.clear();
    _documentDataStoreIndex.clear();
    await Future.wait(
      _fileDataStoreIndex.values.map((dataStore) => dataStore.delete()),
    );
  }
}
