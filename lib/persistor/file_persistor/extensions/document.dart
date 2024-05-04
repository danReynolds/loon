import 'package:loon/loon.dart';
import 'package:loon/persistor/file_persistor/file_persist_document.dart';
import 'package:loon/persistor/file_persistor/file_persistor_settings.dart';

extension DocumentExtensions<T> on Document<T> {
  FilePersistorKey? getPersistenceKey() {
    final documentSettings = persistorSettings;
    if (documentSettings is FilePersistorSettings<T>) {
      final key = documentSettings.key;

      if (key is FilePersistorDocumentKeyBuilder<T>) {
        return (key as FilePersistorDocumentKeyBuilder).build(get()!);
      }

      if (key is FilePersistorCollectionKeyBuilder<T>) {
        return key.build();
      }
    }

    return null;
  }

  /// Returns whether encryption is enabled for this document.
  bool isEncryptionEnabled() {
    final settings = persistorSettings ?? Loon.persistorSettings;

    if (settings is FilePersistorSettings) {
      return settings.encryptionEnabled;
    }

    return false;
  }

  FilePersistDocument<T> toPersistenceDoc() {
    return FilePersistDocument<T>(
      id: id,
      parent: parent,
      encryptionEnabled: isEncryptionEnabled(),
      key: getPersistenceKey(),
      data: getJson(),
    );
  }
}
