import 'dart:convert';
import 'dart:io';
import 'package:encrypt/encrypt.dart';
import 'package:loon/loon.dart';
import 'package:path/path.dart' as path;

final logger = Logger('FileDataStore');

final fileRegex = RegExp(r'^(\w+)(?:\.(encrypted))?\.json$');

class FileDataStore<T> {
  final File file;
  final String name;

  final _store = IndexedValueStore<T>();

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

  T? getNearestEntry(String path) {
    return _store.getNearest(path);
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
          _store.hydrate(jsonDecode(fileStr));
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

  /// Grafts the data at the given [path] in the other [FileDataStore] onto
  /// this data store at that path.
  void graft(FileDataStore other, String path) {
    _store.graft(other._store, path);
  }

  static FileDataStore<Json> parse(
    File file, {
    required Encrypter? encrypter,
  }) {
    final match = fileRegex.firstMatch(path.basename(file.path));
    final name = match!.group(1)!;
    final encryptionEnabled = match.group(2) != null;

    if (encryptionEnabled) {
      if (encrypter == null) {
        throw 'Missing encrypter';
      }

      return EncryptedFileDataStore(
        file: file,
        name: "$name.encrypted",
        encrypter: encrypter,
      );
    }

    return FileDataStore(file: file, name: name);
  }

  static FileDataStore<Json> create(
    String name, {
    required bool encryptionEnabled,
    required Directory directory,
    required Encrypter? encrypter,
  }) {
    if (encryptionEnabled) {
      if (encrypter == null) {
        throw 'Missing encrypter';
      }

      return EncryptedFileDataStore(
        file: File("${directory.path}/$name.encrypted.json"),
        name: "$name.encrypted",
        encrypter: encrypter,
      );
    }

    return FileDataStore(
      file: File("${directory.path}/$name.json"),
      name: name,
    );
  }
}

class EncryptedFileDataStore<T> extends FileDataStore<T> {
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

/// A resolver file data store is a variant of a [FileDataStore] used to store the mapping
/// of documents to the data stores in which those documents are stored. It uses an [IndexedRefValueStore]
/// instead of an [IndexedValueStore] for more efficient determination of the set of values referenced under
/// a given path in the store.
class ResolverFileDataStore extends FileDataStore<String> {
  @override
  // ignore: overridden_fields
  final IndexedRefValueStore<String> _store = IndexedRefValueStore<String>();

  ResolverFileDataStore({required super.file, required super.name});

  Map<String, int> extractRefs([String? path]) {
    return _store.extractRefs(path);
  }
}
