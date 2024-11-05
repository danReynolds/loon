import 'dart:async';
import 'dart:convert';
import 'dart:io';
import 'package:encrypt/encrypt.dart';
import 'package:loon/loon.dart';
import 'package:loon/persistor/data_store.dart';
import 'package:loon/persistor/data_store_resolver.dart';
import 'package:loon/persistor/file_persistor/file_persistor_worker.dart';

final fileRegex = RegExp(r'^(?!__resolver__)(\w+?)(?:.encrypted)?\.json$');

class FileDataStore extends DataStore {
  /// The file associated with the plaintext slice of this data store.
  late final File _plaintextFile;

  /// The file associated with the encrypted slice of this data store.
  late final File _encryptedFile;

  late final Logger _logger;

  final Encrypter encrypter;

  FileDataStore(
    super.name, {
    required Directory directory,
    required this.encrypter,
    super.isHydrated = false,
  }) {
    _logger = Logger(
      'FileDataStore:$name',
      output: FilePersistorWorker.logger.log,
    );
    _plaintextFile = File("${directory.path}/$name.json");
    _encryptedFile = File("${directory.path}/$name.encrypted.json");
  }

  static FileDataStore parse(
    String name, {
    required Encrypter encrypter,
    required Directory directory,
  }) {
    return FileDataStore(
      name,
      directory: directory,
      encrypter: encrypter,
    );
  }

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

  Future<String?> _readFile(File file) {
    return _logger.measure(
      "Read file ${file.path}",
      () async {
        if (await file.exists()) {
          return file.readAsString();
        }

        return null;
      },
    );
  }

  Future<void> _writeFile(File file, String value) {
    return _logger.measure(
      'Write file ${file.path}',
      () => file.writeAsString(value),
    );
  }

  Future<void> _deleteFile(File file) async {
    if (await file.exists()) {
      return _logger.measure('Delete file', () => file.delete());
    }
  }

  Future<void> _hydrate(
    File file,
    DataStoreValueStore store,
  ) async {
    if (!(await file.exists())) {
      return;
    }

    try {
      await _logger.measure(
        'Hydrate ${file.path}',
        () async {
          final value = await _readFile(file);
          if (value != null) {
            final Map json =
                jsonDecode(store.encrypted ? _decrypt(value) : value);

            for (final entry in json.entries) {
              final resolverPath = entry.key;
              final valueStore = ValueStore.fromJson(entry.value);
              store.write(resolverPath, valueStore);
            }
          }
        },
      );
    } catch (e) {
      _logger.log('Corrupt file ${file.path}');
      rethrow;
    }
  }

  @override
  Future<void> hydrate() async {
    if (isHydrated) {
      return;
    }

    await Future.wait([
      _hydrate(_plaintextFile, plaintextStore),
      _hydrate(_encryptedFile, encryptedStore),
    ]);

    isHydrated = true;
  }

  @override
  Future<void> persist() async {
    if (isEmpty) {
      _logger.log('Empty store persist');
      return;
    }

    if (!isDirty) {
      _logger.log('Clean store persist');
      return;
    }

    await _logger.measure(
      'Persist',
      () => Future.wait([
        if (plaintextStore.isDirty)
          _writeFile(
            _plaintextFile,
            jsonEncode(plaintextStore.inspect()),
          ),
        if (encryptedStore.isDirty)
          _writeFile(
            _encryptedFile,
            _encrypt(jsonEncode(encryptedStore.inspect())),
          ),
      ]),
    );

    plaintextStore.isDirty = false;
    encryptedStore.isDirty = false;
  }

  @override
  Future<void> delete() async {
    _deleteFile(_plaintextFile);
    _deleteFile(_encryptedFile);
  }
}

class FileDataStoreResolver extends DataStoreResolver {
  late final File _file;
  late final Logger _logger;

  FileDataStoreResolver({
    required Directory directory,
  }) {
    _logger = Logger(
      'FileDataStoreResolver',
      output: FilePersistorWorker.logger.log,
    );
    _file = File("${directory.path}/${DataStoreResolver.name}.json");

    // Initialize the root of the resolver with the default file data store key.
    // This ensures that all lookups of values in the resolver by parent path roll up
    // to the default store as a fallback if no other value exists for a given path in the resolver.
    store.write(ValueStore.root, Persistor.defaultKey.value);
  }

  @override
  Future<void> hydrate() async {
    try {
      await _logger.measure(
        'Hydrate',
        () async {
          if (await (_file.exists())) {
            final fileStr = await _file.readAsString();
            store = ValueRefStore<String>(jsonDecode(fileStr));
          }
        },
      );
    } catch (e) {
      // If hydration fails for an existing file, then this file data store is corrupt
      // and should be removed from the file data store index.
      _logger.log('Corrupt file.');
      rethrow;
    }
  }

  @override
  Future<void> persist() async {
    if (store.isEmpty) {
      _logger.log('Empty persist');
      return;
    }

    await _logger.measure(
      'Persist',
      () => _file.writeAsString(jsonEncode(store.inspect())),
    );
  }

  @override
  Future<void> delete() async {
    await _logger.measure(
      'Delete',
      () async {
        if (await _file.exists()) {
          await _file.delete();
        }
        store.clear();
        // Re-initialize the root of the store to the default persistor key.
        store.write(ValueStore.root, Persistor.defaultKey.value);
      },
    );
  }

  @override
  Future<void> sync() async {
    if (store.isEmpty) {
      await delete();
    } else if (isDirty) {
      await persist();
    }
  }
}
