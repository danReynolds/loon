/// Live, read-only views of the documents of a collection whose data is one of its subtypes.
///
/// A view is the collection's ordinary query, filtered by type and given a narrower static type
/// with extension types. Its snapshots are the store's own and its lists and streams are its
/// query's, so views need no wrappers, caches or invalidation of their own.
library;

import 'package:loon/src/loon.dart';

extension CollectionViews<T> on Collection<T> {
  /// Views the documents whose data is [S], including subclasses of [S].
  CollectionView<S> view<S extends T>() {
    final test = _TypeTest<S>();
    return CollectionView._((query: where(test.call), test: test));
  }
}

/// A live, read-only view of a collection's documents whose data is a [T].
extension type const CollectionView<T>._(_View _view) implements QueryView<T> {
  /// Views the document [id] while its data is a [T], using this view's type test.
  DocumentView<T> doc(String id) =>
      DocumentView._((doc: _view.query.collection.doc(id), test: _view.test));
}

/// A live, read-only query of a view's documents.
///
/// A view snapshot is its store snapshot, so the view's filters and comparators are its query's.
extension type const QueryView<T>._(_View _view) {
  String get path => _view.query.path;

  List<DocumentSnapshotView<T>> get() =>
      _view.query.get() as List<DocumentSnapshotView<T>>;

  Stream<List<DocumentSnapshotView<T>>> stream() =>
      _view.query.stream() as Stream<List<DocumentSnapshotView<T>>>;

  Stream<List<DocumentChangeSnapshotView<T>>> streamChanges() =>
      _view.query.streamChanges()
          as Stream<List<DocumentChangeSnapshotView<T>>>;

  QueryView<T> where(bool Function(DocumentSnapshotView<T> snap) filter) =>
      _with(_view.query.where(filter as FilterFn<Object?>));

  QueryView<T> sortBy(
    int Function(DocumentSnapshotView<T> a, DocumentSnapshotView<T> b) sort,
  ) =>
      _with(_view.query.sortBy(sort as SortFn<Object?>));

  ObservableQueryView<T> observe({bool multicast = false}) =>
      ObservableQueryView._(
          (query: _view.query.observe(multicast: multicast), test: _view.test));

  QueryView<T> _with(Query<Object?> query) =>
      QueryView._((query: query, test: _view.test));
}

/// An observed [QueryView] with an explicit lifetime, like an [ObservableQuery].
extension type const ObservableQueryView<T>._(
        ({ObservableQuery<Object?> query, _TypeTest<Object?> test}) _view)
    implements QueryView<T> {
  bool get multicast => _view.query.multicast;
  void dispose() => _view.query.dispose();
}

/// A live, read-only view of a document that reads as absent while its data is not a [T].
/// Views of the same document and type are equal.
extension type const DocumentView<T>._(
    ({Document<Object?> doc, _TypeTest<Object?> test}) _view) {
  String get id => _view.doc.id;
  String get path => _view.doc.path;

  DocumentSnapshotView<T>? get() => _select(_view.doc.get());

  bool exists() => get() != null;

  /// The document's snapshots while its data is a [T], and a single null while it is missing or
  /// another type.
  Stream<DocumentSnapshotView<T>?> stream() => _view.doc
      .stream()
      .map(_select)
      .distinct((prev, next) => prev == null && next == null);

  DocumentSnapshotView<T>? _select(DocumentSnapshot<Object?>? snap) =>
      snap != null && _view.test(snap) ? DocumentSnapshotView._(snap) : null;
}

/// A snapshot read through a view, with its data typed as [T].
extension type const DocumentSnapshotView<T>._(
    DocumentSnapshot<Object?> _snap) {
  String get id => _snap.id;
  String get path => _snap.path;
  T get data => _snap.data as T;
}

/// A change to a view's documents. A document that becomes a [T] is added to the view, and one
/// that stops being a [T] is removed from it.
extension type const DocumentChangeSnapshotView<T>._(
    DocumentChangeSnapshot<Object?> _change) {
  String get id => _change.id;
  String get path => _change.path;
  BroadcastEvents get event => _change.event;
  T? get data => _change.data as T?;
  T? get prevData => _change.prevData as T?;
}

/// A view's query, and the type test that selects its documents. A view's documents keep its
/// test, so widening a view's static type never widens what it reads.
typedef _View = ({Query<Object?> query, _TypeTest<Object?> test});

/// Whether a snapshot's data is an [S]. Tests of the same type are equal, so document views of the
/// same document and type are too.
class _TypeTest<S> {
  bool call(DocumentSnapshot<Object?> snap) => snap.data is S;

  @override
  bool operator ==(Object other) => other.runtimeType == runtimeType;

  @override
  int get hashCode => runtimeType.hashCode;
}
