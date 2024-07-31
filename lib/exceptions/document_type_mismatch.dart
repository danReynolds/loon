part of loon;

class DocumentTypeMismatchException<T> implements Exception {
  final Document doc;
  final dynamic data;

  DocumentTypeMismatchException(this.doc, this.data);

  @override
  String toString() =>
      'Document type mismatch: Persisted document ${doc.path} of type $T attempted to read snapshot of type: <${data.runtimeType}>';
}

enum MissingSerializerTypes {
  read,
  write,
}

class MissingSerializerException<T> implements Exception {
  final Document doc;
  final dynamic data;
  final MissingSerializerTypes type;

  MissingSerializerException(this.doc, this.data, this.type);

  @override
  String toString() =>
      'Missing serializer: Persisted document ${doc.path} of type <Document<$T>> attempted to ${type.name} snapshot of type <${data.runtimeType}> without specifying a fromJson/toJson serializer pair.';
}
