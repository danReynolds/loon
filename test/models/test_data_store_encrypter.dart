import 'package:encrypt/encrypt.dart';
import 'package:loon/persistor/data_store_encrypter.dart';

import '../utils.dart';

class TestDataStoreEncrypter extends DataStoreEncrypter {
  @override
  init() async {
    encrypter = Encrypter(AES(testEncryptionKey, mode: AESMode.cbc));
  }

  @override
  String decrypt(String encrypted) {
    final iv = IV.fromBase64(encrypted.substring(0, 24));
    return encrypter.decrypt64(
      encrypted.substring(24),
      iv: iv,
    );
  }
}
