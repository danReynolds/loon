import 'dart:convert';
import 'dart:io';
import 'package:loon/logger.dart';
import 'package:loon/loon.dart';
import 'package:loon/persistor/file_persistor/file_persistor.dart';
import 'package:loon/utils.dart';
import 'package:path/path.dart' as path;

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
    return measureDuration(
      'Write data store $name',
      () => file.writeAsString(value),
    );
  }

  Future<void> delete() async {
    if (!file.existsSync()) {
      printDebug('Attempted to delete non-existent file');
      return;
    }

    await file.delete();
    isDirty = false;
  }

  Future<void> hydrate() async {
    try {
      final fileStr = await readFile();
      await measureDuration(
        'Parse data store $name',
        () async {
          final hydrationData = jsonDecode(fileStr).map(
            (key, dynamic value) => MapEntry(
              key,
              Map<String, dynamic>.from(value),
            ),
          );
          for (final entry in hydrationData.entries) {
            data[entry.key] = entry.value;
          }
        },
      );
    } catch (e) {
      // If hydration fails, then this file data store is corrupt and should be removed from the file data store index.
      printDebug('Corrupt file data store');
      rethrow;
    }
  }

  Future<void> persist() async {
    if (data.isEmpty) {
      printDebug('Attempted to write empty data store');
      return;
    }

    final encodedStore = await measureDuration(
      'Serialize data store $name',
      () async => jsonEncode(data),
    );

    await writeFile(encodedStore);

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
