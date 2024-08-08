import 'package:loon/loon.dart';

/// A [FilePersistDocument] is sent to the worker instead of the [Document] class since that class has additional
/// fields and references that would be unnecessarily copied into the isolate. It also has back references to
/// the [Loon] instance which shouldn't be accessed in the isolate.
class FilePersistDocument<T> {
  /// The path of the document in the store.
  final String path;

  /// The updated document data.
  final dynamic data;

  /// Whether encryption is enabled for this document.
  final bool encrypted;

  FilePersistDocument({
    required this.path,
    required this.data,
    required this.encrypted,
  });
}
