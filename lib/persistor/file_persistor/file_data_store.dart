import 'dart:convert';
import 'dart:io';
import 'package:encrypt/encrypt.dart';
import 'package:loon/loon.dart';
import 'package:path/path.dart' as path;

final fileRegex = RegExp(r'^(\w+)(?:\.(encrypted))?\.json$');

class FileDataStore {
  /// The file associated with the data store.
  final File file;

  /// The name of the file data store.
  final String name;

  /// The data contained within the file data store.
  IndexedValueStore<Json> _store = IndexedValueStore<Json>();

  /// Whether the file data store has pending changes that should be persisted.
  bool isDirty = false;

  /// Whether the file data store has been hydrated yet from its persisted file.
  bool isHydrated;

  static final _logger = Logger('FileDataStore');

  FileDataStore({
    required this.file,
    required this.name,
    this.isHydrated = false,
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

  Future<String> _readFile() {
    return file.readAsString();
  }

  Future<void> _writeFile(String value) {
    return _logger.measure(
      'Write data store $name',
      () => file.writeAsString(value),
    );
  }

  bool hasEntry(String path) {
    return _store.hasPath(path);
  }

  void writeEntry(String path, Json data) {
    _store.write(path, data);
    isDirty = true;
  }

  void removeEntry(String path) {
    if (_store.has(path)) {
      _store.delete(path);
      isDirty = true;
    }
  }

  Future<void> delete() async {
    if (!file.existsSync()) {
      _logger.log('Attempted to delete non-existent file');
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
      await _logger.measure(
        'Parse data store $name',
        () async {
          final fileStr = await _readFile();
          _store = IndexedValueStore.fromJson(jsonDecode(fileStr));
        },
      );
      isHydrated = true;
    } catch (e) {
      if (e is PathNotFoundException) {
        _logger.log('Missing file data store $name');
      } else {
        // If hydration fails for an existing file, then this file data store is corrupt
        // and should be removed from the file data store index.
        _logger.log('Corrupt file data store $name');
        rethrow;
      }
    }
  }

  Future<void> persist() async {
    if (_store.isEmpty) {
      _logger.log('Attempted to write empty data store');
      return;
    }

    final encodedStore = await _logger.measure(
      'Persist data store $name',
      () async => jsonEncode(_store.inspect()),
    );

    await _writeFile(encodedStore);

    isDirty = false;
  }

  bool get isEmpty {
    return _store.isEmpty;
  }

  /// Grafts the data at the given [path] in the other [FileDataStore] onto
  /// this data store at that path.
  void graft(FileDataStore other, String path) {
    _store.graft(other._store, path);
    isDirty = true;
    other.isDirty = true;
  }

  static FileDataStore parse(
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

  static FileDataStore create(
    String name, {
    required bool encrypted,
    required Directory directory,
    required Encrypter? encrypter,
  }) {
    if (encrypted) {
      if (encrypter == null) {
        throw 'Missing encrypter';
      }

      return EncryptedFileDataStore(
        file: File("${directory.path}/$name.encrypted.json"),
        name: "$name.encrypted",
        encrypter: encrypter,
        isHydrated: true,
      );
    }

    return FileDataStore(
      file: File("${directory.path}/$name.json"),
      name: name,
      isHydrated: true,
    );
  }

  /// Returns a flat map of all values in the store by path.
  Map<String, Json> extractValues() {
    return _store.extractValues();
  }
}

class EncryptedFileDataStore extends FileDataStore {
  final Encrypter encrypter;

  EncryptedFileDataStore({
    required super.name,
    required super.file,
    required this.encrypter,
    super.isHydrated = false,
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
  Future<String> _readFile() async {
    return _decrypt(await super._readFile());
  }

  @override
  _writeFile(String value) async {
    return super._writeFile(_encrypt(value));
  }
}

class FileDataStoreResolver {
  late final File _file;

  IndexedRefValueStore<String> store = IndexedRefValueStore<String>();

  static const name = '__resolver__';

  final _logger = Logger('FileDataStoreResolver');

  FileDataStoreResolver({
    required Directory directory,
  }) {
    _file = File("${directory.path}/$name.json");
  }

  Future<void> hydrate() async {
    try {
      await _logger.measure(
        'Hydrate',
        () async {
          final fileStr = await _file.readAsString();
          store = jsonDecode(fileStr);
        },
      );
    } catch (e) {
      if (e is PathNotFoundException) {
        _logger.log('Missing resolver file.');
      } else {
        // If hydration fails for an existing file, then this file data store is corrupt
        // and should be removed from the file data store index.
        _logger.log('Corrupt resolver file.');
        rethrow;
      }
    }
  }

  Future<void> persist() async {
    await _logger.measure(
      'Persist',
      () async {
        if (store.isEmpty) {
          _logger.log('Empty persist');
          return;
        }
        await _file.writeAsString(jsonEncode(store.inspect()));
      },
    );
  }

  Future<void> delete() async {
    await _logger.measure(
      'Delete',
      () async {
        if (!_file.existsSync()) {
          return;
        }
        await _file.delete();
        store.clear();
      },
    );
  }
}
