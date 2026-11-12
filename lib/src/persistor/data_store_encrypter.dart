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

    // Never let an Android decrypt error reset the stored database key. Keep
    // the default namespace and cipher settings so existing keys remain visible.
    const storage = FlutterSecureStorage(
      aOptions: AndroidOptions(resetOnError: false),
    );
    // v11 cannot decrypt some v9 Android ciphers. An ordinary read can return
    // null after a direct upgrade, which would otherwise replace the key and
    // make Loon's existing encrypted stores permanently unreadable.
    final upgrade = await storage.checkUpgradeStatus();
    if (upgrade.hasDataLoss ||
        upgrade.state == SecureStorageUpgradeState.unknown) {
      throw StateError(
        'Loon encryption key is unavailable after a secure-storage upgrade '
        '(${upgrade.state.name}). Do not clear storage or generate a new key; '
        'restore a backup and migrate through flutter_secure_storage v10 '
        'before using v11.',
      );
    }
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

  String encrypt(String plainText) {
    assert(_isInitialized, 'DataStoreEncrypter must be initialized before use');

    final iv = IV.fromSecureRandom(16);
    return iv.base64 + _encrypter.encrypt(plainText, iv: iv).base64;
  }

  String decrypt(String encrypted) {
    assert(_isInitialized, 'DataStoreEncrypter must be initialized before use');

    final iv = IV.fromBase64(encrypted.substring(0, 24));
    return _encrypter.decrypt64(
      encrypted.substring(24),
      iv: iv,
    );
  }
}
