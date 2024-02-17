part of loon;

class DocumentChangeSnapshot<T> extends DocumentSnapshot<T?> {
  final BroadcastEventTypes type;
  final T? prevData;

  DocumentChangeSnapshot({
    required super.doc,
    required super.data,
    required this.type,
    required this.prevData,
  });
}
