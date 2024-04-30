import 'dart:convert';
import 'dart:io';
import 'package:encrypt/encrypt.dart';
import 'package:loon/logger.dart';
import 'package:loon/loon.dart';
import 'package:loon/persistor/file_persistor/file_persist_document.dart';
import 'package:path/path.dart' as path;

final logger = Logger('FileDataStore');

class FileDataStore<T> {
  final File file;
  final String name;

  var _store = IndexedValueStore<T>();

  /// Whether the file data store has pending changes that should be persisted.
  bool isDirty = false;

  bool isHydrated = false;

  FileDataStore({
    required this.file,
    required this.name,
  });

  @override
  bool operator ==(Object other) {
    if (identical(this, other)) {
      return true;
    }
    if (other is FileDataStore) {
      return other.name == name;
    }
    return false;
  }

  @override
  int get hashCode => Object.hashAll([name]);

  T? getEntry(String path) {
    return _store.get(path);
  }

  void writeEntry(String path, T data) {
    _store.write(path, data);
    isDirty = true;
  }

  void removeEntry(String path) {
    if (_store.has(path)) {
      _store.delete(path);
      isDirty = true;
    }
  }

  Future<String> readFile() {
    return file.readAsString();
  }

  Future<void> writeFile(String value) {
    return logger.measure(
      'Write data store $name',
      () => file.writeAsString(value),
    );
  }

  Future<void> delete() async {
    if (!file.existsSync()) {
      logger.log('Attempted to delete non-existent file');
      return;
    }

    await file.delete();
    isDirty = false;
  }

  Future<void> hydrate() async {
    if (isHydrated) {
      return;
    }

    try {
      final fileStr = await readFile();
      await logger.measure(
        'Parse data store $name',
        () async {
          _store = jsonDecode(fileStr);
        },
      );
      isHydrated = true;
    } catch (e) {
      // If hydration fails, then this file data store is corrupt and should be removed from the file data store index.
      logger.log('Corrupt file data store');
      rethrow;
    }
  }

  Future<void> persist() async {
    if (_store.isEmpty) {
      logger.log('Attempted to write empty data store');
      return;
    }

    final encodedStore = await logger.measure(
      'Serialize data store $name',
      () async => jsonEncode(_store.inspect()),
    );

    await writeFile(encodedStore);

    isDirty = false;
  }

  bool get isEmpty {
    return _store.isEmpty;
  }

  Map<String, T> extract() {
    return _store.extract();
  }

  Map<String, T> extractPath(String path) {
    return _store.extractPath(path);
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
        name: '$name.encrypted',
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
