import 'package:encrypt/encrypt.dart';
import 'package:loon/persistor/file_persistor/file_persistor.dart';
import 'package:loon/persistor/file_persistor/file_persistor_settings.dart';

import '../utils.dart';

class TestFilePersistor extends FilePersistor {
  static PersistorCompleter completer = PersistorCompleter();

  TestFilePersistor({
    FilePersistorSettings? settings,
  }) : super(
          // To make tests run faster, in the test environment the persistence throttle
          // is decreased to 1 millisecond.
          settings: (settings ?? const FilePersistorSettings()).copyWith(
            persistenceThrottle: const Duration(milliseconds: 1),
          ),
          onPersist: (_) => completer.persistComplete(),
          onHydrate: (_) => completer.hydrateComplete(),
          onClear: (_) => completer.clearComplete(),
          onClearAll: () => completer.clearAllComplete(),
        );

  @override

  /// Override the initialization of the encrypter to use a test key instead of accessing FlutterSecureStorage
  /// which is not available in the test environment.
  Future<Encrypter?> initEncrypter() async {
    return Encrypter(AES(testEncryptionKey, mode: AESMode.cbc));
  }
}
