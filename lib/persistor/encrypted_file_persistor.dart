import 'dart:io';

import 'package:encrypt/encrypt.dart';
import 'package:flutter_secure_storage/flutter_secure_storage.dart';
import 'package:loon/loon.dart';
import 'package:path/path.dart' as path;

const _secureStorageKey = 'loon_encrypted_file_persistor_key';

class EncryptedFilePersistorSettings<T> extends FilePersistorSettings<T> {
  final bool encryptionEnabled;

  EncryptedFilePersistorSettings({
    required this.encryptionEnabled,
    super.shardFn,
    super.maxShards = 5,
    super.persistenceEnabled = true,
  });
}

class EncryptedFileDataStore extends FileDataStore {
  final Encrypter encrypter;

  EncryptedFileDataStore({
    required super.file,
    required super.collection,
    required this.encrypter,
    super.shard,
  });

  @override
  String get filename {
    return super.filename.replaceFirst('.json', '.encrypted.json');
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

  @override
  Future<String> readFile() async {
    return _decrypt(await super.readFile());
  }

  @override
  writeFile(String value) async {
    await super.writeFile(_encrypt(value));
  }
}

class EncryptedFilePersistor extends FilePersistor {
  late final Encrypter _encrypter;

  @override
  // ignore: overridden_fields
  final filenameRegex =
      RegExp(r'^loon_(\w+)(?:\.(shard_\w+))?\.encrypted\.json$');

  @override
  buildFileDataStoreFilename({
    required String collection,
    required PersistorSettings? settings,
    required String? shard,
  }) {
    final filename = super.buildFileDataStoreFilename(
      collection: collection,
      shard: shard,
      settings: settings,
    );
    if (settings is EncryptedFilePersistorSettings &&
        settings.encryptionEnabled) {
      return filename.replaceFirst('.json', '.encrypted.json');
    }
    return filename;
  }

  @override
  FileDataStore buildFileDataStore({
    required String collection,
    required PersistorSettings? settings,
    required String? shard,
  }) {
    final filename = buildFileDataStoreFilename(
      collection: collection,
      shard: shard,
      settings: settings,
    );

    if (settings is EncryptedFilePersistorSettings &&
        settings.encryptionEnabled) {
      return EncryptedFileDataStore(
        file: File("${fileDataStoreDirectory.path}/$filename"),
        collection: collection,
        encrypter: _encrypter,
      );
    }

    return super.buildFileDataStore(
      collection: collection,
      settings: settings,
      shard: shard,
    );
  }

  @override
  FileDataStore parseFileDataStore({required File file}) {
    final match = filenameRegex.firstMatch(path.basename(file.path))!;

    final collection = match.group(1)!;
    final shard = match.group(2);
    final encryptionEnabled = match.group(3) != null;

    return buildFileDataStore(
      settings:
          EncryptedFilePersistorSettings(encryptionEnabled: encryptionEnabled),
      collection: collection,
      shard: shard,
    );
  }

  @override
  hydrate() async {
    const storage = FlutterSecureStorage();
    final base64Key = await storage.read(key: _secureStorageKey);
    Key key;

    if (base64Key != null) {
      key = Key.fromBase64(base64Key);
    } else {
      key = Key.fromSecureRandom(32);
      await storage.write(key: _secureStorageKey, value: key.base64);
    }
    _encrypter = Encrypter(AES(key, mode: AESMode.cbc));

    return super.hydrate();
  }
}
