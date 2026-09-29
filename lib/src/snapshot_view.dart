part of 'loon.dart';

/// A snapshot whose document handle exposes only read operations.
///
/// The model itself is shared with the store; this does not freeze mutable data.
class DocumentSnapshotView<T> {
  final DocumentView<T> doc;
  final T data;

  DocumentSnapshotView({required this.doc, required this.data});

  String get id => doc.id;
  String get path => doc.path;

  @override
  bool operator ==(Object other) =>
      identical(this, other) ||
      other.runtimeType == runtimeType &&
          other is DocumentSnapshotView<T> &&
          other.doc == doc &&
          other.data == data;

  @override
  int get hashCode => Object.hash(doc, data);
}

/// A change relative to a view's membership. Removed documents have null data.
class DocumentChangeSnapshotView<T> extends DocumentSnapshotView<T?> {
  final BroadcastEvents event;
  final T? prevData;

  DocumentChangeSnapshotView({
    required super.doc,
    required super.data,
    required this.event,
    required this.prevData,
  });

  @override
  bool operator ==(Object other) =>
      identical(this, other) ||
      other.runtimeType == runtimeType &&
          other is DocumentChangeSnapshotView<T> &&
          other.doc == doc &&
          other.data == data &&
          other.prevData == prevData &&
          other.event == event;

  @override
  int get hashCode => Object.hash(doc, event, data, prevData);
}
