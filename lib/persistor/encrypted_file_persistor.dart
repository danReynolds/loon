import 'dart:io';

import 'package:encrypt/encrypt.dart';
import 'package:flutter_secure_storage/flutter_secure_storage.dart';
import 'package:loon/loon.dart';

const _secureStorageKey = 'loon_encrypted_file_persistor_key';

class EncryptedFilePersistorSettings<T> extends FilePersistorSettings<T> {
  final bool isEncrypted;

  EncryptedFilePersistorSettings({
    required this.isEncrypted,
    super.maxShards = 5,
    super.shardFn,
  });
}

class EncryptedFileDataStore extends FileDataStore {
  final String Function(String plainText) encrypt;
  final String Function(String encrypted) decrypt;

  EncryptedFileDataStore({
    required super.collection,
    required super.file,
    required this.encrypt,
    required this.decrypt,
    super.shard,
  });

  @override
  Future<String> readFile() async {
    return decrypt(await super.readFile());
  }

  @override
  writeFile(String value) async {
    await super.writeFile(encrypt(value));
  }
}

class EncryptedFilePersistor extends FilePersistor {
  late final Encrypter _encrypter;

  @override
  // ignore: overridden_fields
  final filenameRegex = RegExp(r'loon_(.*?)(?:_(.*?))?(\.encrypted)?\.json');

  String encrypt(String plainText) {
    final iv = IV.fromSecureRandom(16);
    return iv.base64 + _encrypter.encrypt(plainText, iv: iv).base64;
  }

  String decrypt(String encrypted) {
    final iv = IV.fromBase64(encrypted.substring(0, 24));
    return _encrypter.decrypt64(
      encrypted.substring(24),
      iv: iv,
    );
  }

  @override
  buildFileDataStoreFilename({
    required String collection,
    required PersistorSettings? settings,
    String? shard,
  }) {
    final filename = super.buildFileDataStoreFilename(
      collection: collection,
      shard: shard,
      settings: settings,
    );

    if (settings != null && settings is EncryptedFilePersistorSettings) {
      if (!settings.isEncrypted) {
        return filename;
      }
    }

    return filename.replaceFirst('.json', '.encrypted.json');
  }

  @override
  FileDataStore buildFileDataStore({required File file}) {
    final match = filenameRegex.firstMatch(file.path)!;

    final collection = match.group(1)!;
    final shard = match.group(2);
    final isEncrypted = match.group(3) != null;

    if (isEncrypted) {
      return EncryptedFileDataStore(
        encrypt: encrypt,
        decrypt: decrypt,
        collection: collection,
        file: file,
        shard: shard,
      );
    }
    return super.buildFileDataStore(file: file);
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
