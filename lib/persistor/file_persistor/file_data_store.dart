import 'dart:convert';
import 'dart:io';
import 'package:encrypt/encrypt.dart';
import 'package:loon/loon.dart';

final logger = Logger('FileDataStore');

final fileRegex = RegExp(r'^(\w+)(?:\.(encrypted))?\.json$');

class FileDataStore {
  final File file;
  final String name;
  late final IndexedValueStore<Json> _store;

  /// Whether the file data store has pending changes that should be persisted.
  bool isDirty = false;

  bool isHydrated = false;

  FileDataStore({
    required this.file,
    required this.name,
    IndexedValueStore<Json>? store,
  }) {
    _store = store ?? IndexedValueStore<Json>();
  }

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
    return logger.measure(
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
      final fileStr = await _readFile();
      await logger.measure(
        'Parse data store $name',
        () async {
          final hydratedStore = IndexedValueStore.fromJson(jsonDecode(fileStr));
          // The file data store can have data marked for persistence before it is hydrated,
          // in which case the pending data is grafted into the hydrated data.
          hydratedStore.graft(_store);
          _store = hydratedStore;
        },
      );
      isHydrated = true;
    } catch (e) {
      if (e is PathNotFoundException) {
        logger.log('Missing file data store $name');
      } else {
        // If hydration fails for an existing file, then this file data store is corrupt
        // and should be removed from the file data store index.
        logger.log('Corrupt file data store $name');
        rethrow;
      }
    }
  }

  Future<void> persist() async {
    if (_store.isEmpty) {
      logger.log('Attempted to write empty data store');
      return;
    }

    // A data store must be hydrated before it can be persisted, since data stores
    // are not written incrementally and must merge all of its data before writing
    // to its underlying file.
    if (!isHydrated) {
      await hydrate();
    }

    final encodedStore = await logger.measure(
      'Serialize data store $name',
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
  }

  static FileDataStore create(
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

  /// Returns a flat map of all values in the store by path.
  Map<String, Json> extractValues() {
    return _store.extractValues();
  }

  /// Extracts the meta data for the store into [Json].
  Json extractMeta() {
    return {
      "name": name,
      // Only the structure of the store is serialized, its values are not required.
      "data": _store.extractStructure(),
      "encryptionEnabled": this is EncryptedFileDataStore,
    };
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
  Future<String> _readFile() async {
    return _decrypt(await super._readFile());
  }

  @override
  _writeFile(String value) async {
    return super._writeFile(_encrypt(value));
  }
}

/// The [MetaFileDataStore] stores an index of each existing file data store's meta data including:
/// 1. The name of the store.
/// 2. The structure of the store's current data (used for determining which stores to hydrate by path).
/// 3. The encryption status of the store.
class MetaFileDataStore {
  final Map<String, FileDataStore> index;
  final Encrypter? encrypter;
  late final File _file;

  static const name = '__meta__';

  MetaFileDataStore({
    required this.index,
    required this.encrypter,
    required Directory directory,
  }) {
    _file = File("${directory.path}/$name.json");
  }

  /// Initializes each [FileDataStore] using the meta data stored in the [MetaFileDataStore]. Does *not*
  /// hydrate the file data stores, since that is done on-demand by the client.
  Future<void> hydrate() async {
    try {
      await logger.measure(
        'Hydrate meta data store',
        () async {
          final fileStr = await _file.readAsString();
          final Json json = jsonDecode(fileStr);

          for (final entry in json.entries) {
            final metaJson = entry.value;
            index[entry.key] = FileDataStore.create(
              name,
              encryptionEnabled: metaJson['encryptionEnabled'],
              directory: _file.parent,
              encrypter: encrypter,
            );
          }
        },
      );
    } catch (e) {
      if (e is PathNotFoundException) {
        logger.log('Missing file data store resolver');
      } else {
        logger.log('Corrupt file data store resolver');
        rethrow;
      }
    }
  }

  /// Persists the meta file data store which consists of a mapping of all file data stores
  /// by name to their meta data including their name, encryption status and the structure
  /// of the data contained in their data store.
  Future<void> persist() async {
    await logger.measure(
      'Persist meta data store',
      () async {
        final data = {};
        for (final entry in index.entries) {
          data[entry.key] = entry.value.extractMeta();
        }
        await _file.writeAsString(jsonEncode(data));
      },
    );
  }

  Future<void> delete() async {
    await logger.measure(
      'Delete meta data store',
      () async {
        await _file.delete();
      },
    );
  }
}
