part of loon;

class DocumentChangeSnapshot<T> extends DocumentSnapshot<T?> {
  final BroadcastEvents event;
  final T? prevData;

  DocumentChangeSnapshot({
    required super.doc,
    required super.data,
    required this.event,
    required this.prevData,
  });

  @override
  bool operator ==(Object other) {
    if (identical(this, other)) {
      return true;
    }
    if (other is DocumentChangeSnapshot<T>) {
      return other.doc == doc &&
          other.event == event &&
          other.data == data &&
          other.prevData == prevData;
    }
    return false;
  }

  @override
  int get hashCode => Object.hashAll([doc, event, data, prevData]);
}
