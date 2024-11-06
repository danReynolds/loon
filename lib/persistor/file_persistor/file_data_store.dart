import 'dart:async';
import 'dart:convert';
import 'dart:io';
import 'package:encrypt/encrypt.dart';
import 'package:loon/loon.dart';
import 'package:loon/persistor/data_store.dart';
import 'package:loon/persistor/file_persistor/file_persistor_worker.dart';

final fileRegex = RegExp(r'^(?!__resolver__)(\w+?)(?:.encrypted)?\.json$');

class FileDataStore extends DataStore {
  /// The file associated with the plaintext slice of this data store.
  late final File _plaintextFile;

  /// The file associated with the encrypted slice of this data store.
  late final File _encryptedFile;

  late final Logger _logger;

  FileDataStore(
    super.name, {
    required Directory directory,
    required super.encrypter,
    super.isHydrated = false,
  }) {
    _logger = Logger(
      'FileDataStore:$name',
      output: FilePersistorWorker.logger.log,
    );
    _plaintextFile = File("${directory.path}/$name.json");
    _encryptedFile = File(
      "${directory.path}/$name.${Persistor.encryptedKey}.json",
    );
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
                jsonDecode(store.encrypted ? decrypt(value) : value);

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
            encrypt(jsonEncode(encryptedStore.inspect())),
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
