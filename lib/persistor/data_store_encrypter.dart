import 'package:encrypt/encrypt.dart';
import 'package:flutter_secure_storage/flutter_secure_storage.dart';

class DataStoreEncrypter {
  late final Encrypter _encrypter;

  static const _secureStorageKey = 'loon_encrypted_file_persistor_key';
  static const encryptedName = 'encrypted';

  bool _isInitialized = false;

  DataStoreEncrypter([Encrypter? encrypter]) {
    if (encrypter != null) {
      _encrypter = encrypter;
      _isInitialized = true;
    }
  }

  Future<void> init() async {
    if (_isInitialized) {
      return;
    }

    Key key;

    const storage = FlutterSecureStorage();
    final base64Key = await storage.read(key: _secureStorageKey);
    if (base64Key != null) {
      key = Key.fromBase64(base64Key);
    } else {
      key = Key.fromSecureRandom(32);
      await storage.write(key: _secureStorageKey, value: key.base64);
    }

    _encrypter = Encrypter(AES(key, mode: AESMode.cbc));
    _isInitialized = true;
  }

  Future<String> encrypt(String plainText) async {
    await init();

    final iv = IV.fromSecureRandom(16);
    return iv.base64 + _encrypter.encrypt(plainText, iv: iv).base64;
  }

  Future<String> decrypt(String encrypted) async {
    await init();

    final iv = IV.fromBase64(encrypted.substring(0, 24));
    return _encrypter.decrypt64(
      encrypted.substring(24),
      iv: iv,
    );
  }
}
