import 'package:encrypt/encrypt.dart';
import 'package:loon/persistor/file_persistor/file_persistor.dart';
import 'package:loon/persistor/file_persistor/file_persistor_settings.dart';

import '../utils.dart';

class TestFilePersistor extends FilePersistor {
  static PersistorCompleter completer = PersistorCompleter();

  final encrypter = Encrypter(AES(testEncryptionKey, mode: AESMode.cbc));

  TestFilePersistor({
    FilePersistorSettings? settings,
  }) : super(
          // To make tests run faster, in the test environment the persistence throttle
          // is decreased to 1 millisecond.
          persistenceThrottle: const Duration(milliseconds: 1),
          settings: settings ?? const FilePersistorSettings(),
          onPersist: (_) => completer.persistComplete(),
          onHydrate: (_) => completer.hydrateComplete(),
          onClear: (_) => completer.clearComplete(),
          onClearAll: () => completer.clearAllComplete(),
        );

  @override

  /// Override the initialization of the encrypter to use a test key instead of accessing FlutterSecureStorage
  /// which is not available in the test environment.
  Future<Encrypter?> initEncrypter() async {
    return encrypter;
  }

  String decrypt(String encrypted) {
    final iv = IV.fromBase64(encrypted.substring(0, 24));
    return encrypter.decrypt64(
      encrypted.substring(24),
      iv: iv,
    );
  }
}
