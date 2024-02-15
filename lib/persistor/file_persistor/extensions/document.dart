import 'package:loon/loon.dart';
import 'package:loon/persistor/file_persistor/file_persist_document.dart';

extension DocumentExtensions<T> on Document<T> {
  /// Returns the name of a file data store name for a given document and its persistor settings.
  /// Uses the custom persistence key of the document if specified in its persistor settings,
  /// otherwise it defaults to the document's collection name.
  String getDatastoreName() {
    String dataStoreName;
    final documentSettings = persistorSettings;

    if (documentSettings is FilePersistorSettings) {
      dataStoreName =
          documentSettings.getPersistenceKey?.call(this) ?? collection;

      if (isEncryptionEnabled()) {
        dataStoreName += '.encrypted';
      }
    } else {
      dataStoreName = collection;
    }

    return dataStoreName;
  }

  /// Returns whether encryption is enabled for this document.
  bool isEncryptionEnabled() {
    return persistorSettings is EncryptedFilePersistorSettings &&
        (persistorSettings as EncryptedFilePersistorSettings).encryptionEnabled;
  }

  FilePersistDocument toPersistenceDoc() {
    return FilePersistDocument(
      key: key,
      encryptionEnabled: isEncryptionEnabled(),
      dataStoreName: getDatastoreName(),
      data: getJson(),
    );
  }
}
