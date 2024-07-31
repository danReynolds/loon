import 'package:loon/loon.dart';
import 'package:loon/persistor/file_persistor/file_persistor_settings.dart';

/// A file data store document is a minimal data model that is sent to the [FilePersistorWorker]
/// isolate and persisted in the [FileDataStore] of name [dataStoreName] with the updated document data.
///
/// [FilePersistDocument] is sent to the worker instead of the [Document] class since that class has additional
/// fields and references that would be unnecessarily copied into the isolate. It also has back references to
/// the [Loon] instance which shouldn't be accessed in the isolate.
class FilePersistDocument<T> {
  /// The document collection path.
  final String parent;

  /// The document ID.
  final String id;

  /// The persistence key to use for the document. If not specified, defaults to the
  /// document's top-level collection key.
  final FilePersistorKey? key;

  /// The updated document data.
  final dynamic data;

  /// Whether encryption is enabled for this document.
  final bool encrypted;

  FilePersistDocument({
    required this.id,
    required this.parent,
    required this.key,
    required this.data,
    required this.encrypted,
  });

  String get path {
    return "${parent}__$id";
  }
}
