class PersistenceDocument<T> {
  /// The path of the document in the store.
  final String path;

  /// The updated document data.
  final dynamic data;

  /// Whether encryption is enabled for this document.
  final bool encrypted;

  PersistenceDocument({
    required this.path,
    required this.data,
    required this.encrypted,
  });
}
