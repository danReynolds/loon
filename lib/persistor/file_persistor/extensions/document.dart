import 'package:loon/loon.dart';
import 'package:loon/persistor/file_persistor/file_persist_document.dart';
import 'package:loon/persistor/file_persistor/file_persistor_settings.dart';

extension DocumentExtensions<T> on Document<T> {
  FilePersistorKey? getPersistenceKey() {
    final documentSettings = persistorSettings;
    if (documentSettings is FilePersistorSettings) {
      return switch (documentSettings.key) {
        FilePersistorCollectionKeyBuilder builder => builder.build(),
        FilePersistorDocumentKeyBuilder(builder: final builder) =>
          builder(get()!),
        _ => null,
      };
    }

    return null;
  }

  /// Returns whether encryption is enabled for this document.
  bool isEncryptionEnabled() {
    return persistorSettings is FilePersistorSettings &&
        (persistorSettings as FilePersistorSettings).encryptionEnabled;
  }

  FilePersistDocument toPersistenceDoc() {
    return FilePersistDocument(
      id: id,
      parent: parent,
      encryptionEnabled: isEncryptionEnabled(),
      key: getPersistenceKey(),
      data: getJson(),
    );
  }
}
