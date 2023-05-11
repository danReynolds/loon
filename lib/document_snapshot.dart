part of loon;

class DocumentSnapshot<T> {
  final Document<T> doc;
  final T data;

  DocumentSnapshot({
    required this.doc,
    required this.data,
  });

  String get id {
    return doc.id;
  }

  String get collection {
    return doc.collection;
  }
}
