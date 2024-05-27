import 'package:loon/loon.dart';
import 'package:loon/persistor/file_persistor/file_persist_document.dart';
import 'package:loon/persistor/file_persistor/file_persistor_settings.dart';

extension DocumentExtensions<T> on Document<T> {
  FilePersistorKey? getPersistenceKey() {
    final documentSettings = persistorSettings;
    if (documentSettings is FilePersistorSettings<T>) {
      final keyBuilder = documentSettings.key;

      if (keyBuilder is FilePersistorDocumentKeyBuilder<T>) {
        return (keyBuilder as FilePersistorDocumentKeyBuilder).build(get()!);
      }

      if (keyBuilder is FilePersistorCollectionKeyBuilder<T>) {
        return keyBuilder.build();
      }
    }

    return null;
  }

  /// Returns whether encryption is enabled for this document.
  bool isEncrypted() {
    final settings = persistorSettings ?? Loon.persistorSettings;

    if (settings is FilePersistorSettings) {
      return settings.encrypted;
    }

    return false;
  }

  FilePersistDocument<T> toPersistenceDoc() {
    return FilePersistDocument<T>(
      id: id,
      parent: parent,
      encrypted: isEncrypted(),
      key: getPersistenceKey(),
      data: getJson(),
    );
  }
}
