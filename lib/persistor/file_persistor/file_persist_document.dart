import 'package:loon/loon.dart';

/// A file data store document is a minimal data model that is sent to the [FilePersistorWorker]
/// isolate and persisted in the [FileDataStore] of name [dataStoreName] with the updated document data.
///
/// [FilePersistDocument] is sent to the worker instead of the [Document] class since that class has additional
/// fields and references that would be unnecessarily copied into the isolate. It also has back references to
/// the [Loon] instance which shouldn't be accessed in the isolate.
class FilePersistDocument {
  /// The document key of format collection:id.
  final String key;

  /// The name of the file data store that the document should be persisted in.
  final String dataStoreName;

  /// The updated document data.
  final Json? data;

  /// Whether encryption is enabled for this document.
  final bool encryptionEnabled;

  FilePersistDocument({
    required this.key,
    required this.dataStoreName,
    required this.data,
    required this.encryptionEnabled,
  });
}
