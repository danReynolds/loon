/// Live, read-only views of the documents whose data is one subtype of their collection's type.
///
/// A view is an ordinary query or document filtered by type and given a narrower static type
/// with extension types. Its snapshots, lists and streams are the store's own, so views need no
/// wrappers, caches or invalidation of their own.
library;

import 'package:flutter/widgets.dart';
import 'package:loon/src/loon.dart';
import 'package:loon/src/widgets/document_stream_builder.dart';
import 'package:loon/src/widgets/query_stream_builder.dart';

extension CollectionViews<T> on Collection<T> {
  /// Views the documents whose data is [S], including subclasses of [S].
  QueryView<S> view<S extends T>() => QueryView._(where(_TypeTest<S>().call));
}

extension DocumentViews<T> on Document<T> {
  /// Views the document while its data is [S], including subclasses of [S].
  DocumentView<S> view<S extends T>() =>
      DocumentView._((doc: this, test: _TypeTest<S>()));
}

/// A snapshot read through a view, with its data typed as [T].
extension type const DocumentSnapshotView<T>._(
    DocumentSnapshot<Object?> _snap) {
  String get id => _snap.id;
  String get path => _snap.path;
  T get data => _snap.data as T;
}

/// A change to a view's results. A document that becomes a [T] is added to the view, and one
/// that stops being a [T] is removed from it.
extension type const DocumentChangeSnapshotView<T>._(
    DocumentChangeSnapshot<Object?> _change) {
  String get id => _change.id;
  String get path => _change.path;
  BroadcastEvents get event => _change.event;
  T? get data => _change.data as T?;
  T? get prevData => _change.prevData as T?;
}

/// A live, read-only query of the documents whose data is a [T].
///
/// A view snapshot is its store snapshot, so the view's filters and comparators are its query's.
extension type const QueryView<T>._(Query<Object?> _query) {
  String get path => _query.path;

  List<DocumentSnapshotView<T>> get() =>
      _query.get() as List<DocumentSnapshotView<T>>;

  Stream<List<DocumentSnapshotView<T>>> stream() =>
      _query.stream() as Stream<List<DocumentSnapshotView<T>>>;

  Stream<List<DocumentChangeSnapshotView<T>>> streamChanges() =>
      _query.streamChanges() as Stream<List<DocumentChangeSnapshotView<T>>>;

  QueryView<T> where(bool Function(DocumentSnapshotView<T> snap) filter) =>
      QueryView._(_query.where(filter as FilterFn<Object?>));

  QueryView<T> sortBy(
    int Function(DocumentSnapshotView<T> a, DocumentSnapshotView<T> b) sort,
  ) =>
      QueryView._(_query.sortBy(sort as SortFn<Object?>));

  ObservableQueryView<T> observe({bool multicast = false}) =>
      ObservableQueryView._(_query.observe(multicast: multicast));
}

/// An observed [QueryView] with an explicit lifetime, like an [ObservableQuery].
extension type const ObservableQueryView<T>._(
    ObservableQuery<Object?> _observer) implements QueryView<T> {
  bool get multicast => _observer.multicast;
  void dispose() => _observer.dispose();
}

/// A live, read-only view of a document that reads as absent while its data is not a [T].
/// Views of the same document and type are equal.
extension type const DocumentView<T>._(
    ({Document<Object?> doc, _TypeTest<Object?> test}) _view) {
  String get id => _view.doc.id;
  String get path => _view.doc.path;

  DocumentSnapshotView<T>? get() => _select(_view.doc.get());

  bool exists() => get() != null;

  Stream<DocumentSnapshotView<T>?> stream() => _view.doc
      .stream()
      .map(_select)
      .distinct((prev, next) => prev == null && next == null);

  DocumentSnapshotView<T>? _select(DocumentSnapshot<Object?>? snap) =>
      snap != null && _view.test(snap) ? DocumentSnapshotView._(snap) : null;
}

/// Whether a snapshot's data is an [S]. Tests compare by type, so they can key a document view.
class _TypeTest<S> {
  bool call(DocumentSnapshot<Object?> snap) => snap.data is S;

  @override
  bool operator ==(Object other) => other.runtimeType == runtimeType;

  @override
  int get hashCode => runtimeType.hashCode;
}

/// Builds with the snapshots of a [QueryView].
class QueryViewStreamBuilder<T> extends StatelessWidget {
  final QueryView<T> query;
  final Widget Function(BuildContext, List<DocumentSnapshotView<T>>) builder;

  const QueryViewStreamBuilder({
    super.key,
    required this.query,
    required this.builder,
  });

  @override
  Widget build(BuildContext context) => QueryStreamBuilder<Object?>(
        query: query._query,
        builder: (context, snaps) =>
            builder(context, snaps as List<DocumentSnapshotView<T>>),
      );
}

/// Builds with the snapshot of a [DocumentView], or null while it is missing or not a [T].
class DocumentViewStreamBuilder<T> extends StatelessWidget {
  final DocumentView<T> doc;
  final Widget Function(BuildContext, DocumentSnapshotView<T>?) builder;

  const DocumentViewStreamBuilder({
    super.key,
    required this.doc,
    required this.builder,
  });

  @override
  Widget build(BuildContext context) => DocumentStreamBuilder<Object?>(
        doc: doc._view.doc,
        builder: (context, snap) => builder(context, doc._select(snap)),
      );
}
