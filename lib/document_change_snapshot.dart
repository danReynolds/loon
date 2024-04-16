part of loon;

class DocumentChangeSnapshot<T> extends DocumentSnapshot<T?> {
  final EventTypes event;
  final T? prevData;

  DocumentChangeSnapshot({
    required super.doc,
    required super.data,
    required this.event,
    required this.prevData,
  });
}
