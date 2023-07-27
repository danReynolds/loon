import 'dart:convert';
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
    required this.encrypter,
    required super.collectionPath,
    required super.file,
    required super.shard,
  });

  static String encrypt(Encrypter encrypter, String plainText) {
    final iv = IV.fromSecureRandom(16);
    return iv.base64 + encrypter.encrypt(plainText, iv: iv).base64;
  }

  static String decrypt(Encrypter encrypter, String encrypted) {
    final iv = IV.fromBase64(encrypted.substring(0, 24));
    return encrypter.decrypt64(
      encrypted.substring(24),
      iv: iv,
    );
  }

  static Future<FileDataStore> fromFile(File file, Encrypter encrypter) async {
    final json = await jsonDecode(decrypt(
      encrypter,
      await file.readAsString(),
    ));

    final meta = json['meta'];
    final dataJson = json['data'];

    return FileDataStore(
      file: file,
      collectionPath: meta['collectionPath'],
      shard: meta['shard'],
      data: dataJson.map(
        (key, dynamic value) => MapEntry(
          key,
          Map<String, dynamic>.from(value),
        ),
      ),
    );
  }

  @override
  Future<void> persist() async {
    await file.writeAsString(encrypt(encrypter, jsonEncode(toJson())));
  }
}

class EncryptedFilePersistor extends FilePersistor {
  late final Encrypter _encrypter;
  final encryptedFilenameRegex = RegExp(r'^loon_.*\.encrypted\.json$');

  @override
  buildFileDataStore({
    required String collectionPath,
    required String? shard,
    required PersistorSettings? persistorSettings,
  }) {
    final fileDataStoreId = buildFileDataStoreId(
      collectionPath: collectionPath,
      shard: shard,
    );

    if (persistorSettings is EncryptedFilePersistorSettings &&
        persistorSettings.encryptionEnabled) {
      return EncryptedFileDataStore(
        encrypter: _encrypter,
        collectionPath: collectionPath,
        shard: shard,
        file: File(
          '${fileDataStoreDirectory.path}/loon_$fileDataStoreId.encrypted.json',
        ),
      );
    }

    return FileDataStore(
      collectionPath: collectionPath,
      shard: shard,
      file: File('${fileDataStoreDirectory.path}/loon_$fileDataStoreId.json'),
    );
  }

  @override
  Future<List<FileDataStore>> buildFileDataStores() async {
    final files = await readDataStoreFiles();

    return Future.wait(files.map((file) {
      if (encryptedFilenameRegex.hasMatch(path.basename(file.path))) {
        return EncryptedFileDataStore.fromFile(file, _encrypter);
      }
      return FileDataStore.fromFile(file);
    }).toList());
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
