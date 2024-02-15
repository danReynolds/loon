import 'dart:convert';
import 'dart:io';
import 'package:encrypt/encrypt.dart';
import 'package:loon/loon.dart';
import 'package:loon/persistor/file_persistor/file_persist_document.dart';
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

class EncryptedFileDataStore extends FileDataStore {
  final Encrypter encrypter;

  EncryptedFileDataStore({
    required super.name,
    required super.file,
    required this.encrypter,
  });

  String _encrypt(String plainText) {
    final iv = IV.fromSecureRandom(16);
    return iv.base64 + encrypter.encrypt(plainText, iv: iv).base64;
  }

  String _decrypt(String encrypted) {
    final iv = IV.fromBase64(encrypted.substring(0, 24));
    return encrypter.decrypt64(
      encrypted.substring(24),
      iv: iv,
    );
  }

  @override
  Future<String> readFile() async {
    return _decrypt(await super.readFile());
  }

  @override
  writeFile(String value) async {
    return super.writeFile(_encrypt(value));
  }
}

/// A factory for building a [FileDataStore] on the worker.
class FileDataStoreFactory {
  final fileRegex = RegExp(r'^(\w+)(?:\.(encrypted))?\.json$');

  final Encrypter? encrypter;

  /// The directory in which a file data store is persisted.
  final Directory directory;

  FileDataStoreFactory({
    required this.directory,
    required this.encrypter,
  });

  FileDataStore fromFile(File file) {
    final match = fileRegex.firstMatch(path.basename(file.path));
    final name = match!.group(1)!;
    final encryptionEnabled = match.group(2) != null;

    if (encryptionEnabled) {
      if (encrypter == null) {
        throw 'Missing encrypter';
      }

      return EncryptedFileDataStore(
        name: name,
        file: file,
        encrypter: encrypter!,
      );
    }

    return FileDataStore(
      file: file,
      name: name,
    );
  }

  FileDataStore fromDoc(FilePersistDocument doc) {
    final file = File("${directory.path}/${doc.dataStoreName}.json");
    final name = doc.dataStoreName;

    if (doc.encryptionEnabled) {
      if (encrypter == null) {
        throw 'Missing encrypter';
      }

      return EncryptedFileDataStore(
        file: file,
        name: name,
        encrypter: encrypter!,
      );
    }

    return FileDataStore(
      file: file,
      name: name,
    );
  }
}
