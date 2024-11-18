part of '../loon.dart';

class DocumentTypeMismatchException<T> implements Exception {
  final Document doc;
  final dynamic data;

  DocumentTypeMismatchException(this.doc, this.data);

  @override
  String toString() =>
      'Document type mismatch: Document ${doc.path} of type <$T> attempted to read snapshot of type: <${data.runtimeType}>';
}

enum MissingSerializerEvents {
  read,
  write,
}

class MissingSerializerException<T> implements Exception {
  final Document doc;
  final dynamic data;
  final MissingSerializerEvents event;

  MissingSerializerException(this.doc, this.data, this.event);

  @override
  String toString() =>
      'Missing serializer: Persisted document ${doc.path} of type <Document<$T>> attempted to ${event.name} snapshot of type <${data.runtimeType}> without specifying a fromJson/toJson serializer pair.';
}
