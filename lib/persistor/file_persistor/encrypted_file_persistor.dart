import 'dart:io';

import 'package:encrypt/encrypt.dart';
import 'package:flutter_secure_storage/flutter_secure_storage.dart';
import 'package:loon/loon.dart';
import 'package:loon/persistor/file_persistor/file_persistor.dart';
import 'package:path/path.dart' as path;

const _secureStorageKey = 'loon_encrypted_file_persistor_key';

class EncryptedFilePersistorSettings<T> extends FilePersistorSettings<T> {
  final bool encryptionEnabled;

  EncryptedFilePersistorSettings({
    required this.encryptionEnabled,
    super.persistenceEnabled = true,
  });
}

class EncryptedFileDataStore extends FileDataStore {
  final bool encryptionEnabled;
  final Encrypter encrypter;

  EncryptedFileDataStore({
    required super.name,
    required super.file,
    required this.encrypter,
    required this.encryptionEnabled,
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
    if (encryptionEnabled) {
      return _decrypt(await super.readFile());
    }
    return super.readFile();
  }

  @override
  writeFile(String value) async {
    if (encryptionEnabled) {
      return super.writeFile(_encrypt(value));
    }
    return super.writeFile(value);
  }
}

class EncryptedFileDataStoreFactory extends FileDataStoreFactory {
  final Encrypter encrypter;

  @override
  // ignore: overridden_fields
  final RegExp fileRegex = RegExp(r'^loon_(\w+)(?:\.(encrypted))?\.json$');

  EncryptedFileDataStoreFactory({
    required super.directory,
    required super.persistorSettings,
    required this.encrypter,
  });

  @override
  getDocumentDataStoreName(doc) {
    final documentDataStoreName = super.getDocumentDataStoreName(doc);

    if (doc.isPersistenceEnabled()) {
      return "$documentDataStoreName.encrypted";
    }

    return documentDataStoreName;
  }

  @override
  EncryptedFileDataStore fromFile(File file) {
    final match = fileRegex.firstMatch(path.basename(file.path));
    final name = match!.group(1)!;
    final encryptionEnabled = match.group(2) != null;

    return EncryptedFileDataStore(
      name: name,
      file: file,
      encrypter: encrypter,
      encryptionEnabled: encryptionEnabled,
    );
  }

  @override
  EncryptedFileDataStore fromDoc(doc) {
    final name = getDocumentDataStoreName(doc);

    return EncryptedFileDataStore(
      file: File("${directory.path}/$name.json"),
      name: name,
      encrypter: encrypter,
      encryptionEnabled: doc.isPersistenceEnabled(),
    );
  }
}

class EncryptedFilePersistor extends FilePersistor {
  late final Encrypter _encrypter;

  EncryptedFilePersistor({
    super.persistenceThrottle = const Duration(milliseconds: 100),
    super.persistorSettings,
  });

  Future<void> _initEncrypter() async {
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
  }

  @override
  init() async {
    await Future.wait([
      _initEncrypter(),
      initStorageDirectory(),
    ]);

    factory = EncryptedFileDataStoreFactory(
      encrypter: _encrypter,
      directory: fileDataStoreDirectory,
      persistorSettings: persistorSettings,
    );
  }
}
