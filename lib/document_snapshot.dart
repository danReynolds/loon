part of loon;

/// A snapshot of a document's data and dependencies at any given moment.
class DocumentSnapshot<T> {
  final Document<T> doc;
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
  int get hashCode => Object.hashAll([doc, data]);

  String get id {
    return doc.id;
  }

  String get path {
    return doc.path;
  }
}
