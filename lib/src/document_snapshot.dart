part of 'loon.dart';

/// A snapshot of a document's data and dependencies at any given moment.
class DocumentSnapshot<T> implements DocumentSnapshotView<T> {
  @override
  final Document<T> doc;
  @override
  final T data;

  DocumentSnapshot({
    required this.doc,
    required this.data,
  });

  @override
  bool operator ==(Object other) {
    if (identical(this, other)) {
      return true;
    }
    if (other is DocumentSnapshot<T>) {
      return other.doc == doc && other.data == data;
    }
    return false;
  }

  @override
  int get hashCode => Object.hash(doc, data);

  @override
  String get id {
    return doc.id;
  }

  @override
  String get path {
    return doc.path;
  }
}
