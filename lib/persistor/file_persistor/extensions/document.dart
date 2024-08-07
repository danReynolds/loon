import 'package:loon/loon.dart';
import 'package:loon/persistor/file_persistor/file_persistor_settings.dart';

extension DocumentExtensions<T> on Document<T> {
  /// Returns whether encryption is enabled for this document.
  bool isEncrypted() {
    final settings = persistorSettings ?? Loon.persistorSettings;
    if (settings is FilePersistorSettings) {
      return settings.encrypted;
    }

    return false;
  }
}
