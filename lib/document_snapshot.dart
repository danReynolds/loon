part of loon;

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
      return other.data == data && other.doc == doc;
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
