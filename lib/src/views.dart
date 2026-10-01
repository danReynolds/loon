part of 'loon.dart';

class CollectionView<T> extends QueryView<T> {
  CollectionView._(super.query) : super._();

  DocumentView<T> doc(String id) => DocumentView(_query.collection.doc(id));
}

typedef QueryViewFilterFn<T> = bool Function(DocumentSnapshotView<T>);
typedef QueryViewSortByFn<T> = int Function(
    DocumentSnapshotView<T> a, DocumentSnapshotView<T> b);

class QueryView<T> {
  /// The query that selects the view's documents: those of type [T] that pass its filters.
  final Query _query;
  final QueryViewSortByFn<T>? _sortBy;

  /// Views the documents of [query] whose data is a [T].
  QueryView._(Query query)
      : this._selected(query.where((snap) => snap.data is T));

  QueryView._selected(this._query, {QueryViewSortByFn<T>? sortBy})
      : _sortBy = sortBy;

  String get path => _query.path;

  // The query has already selected the view's documents, so they are only wrapped and sorted.
  List<DocumentSnapshotView<T>> _convert(List<DocumentSnapshot> snaps) {
    final views = [for (final snap in snaps) DocumentSnapshotView<T>._(snap)];
    if (_sortBy case final sortBy?) {
      views.sort(sortBy);
    }
    return views;
  }

  List<DocumentSnapshotView<T>> get() => _convert(_query.get());

  Stream<List<DocumentSnapshotView<T>>> stream() =>
      _query.stream().map(_convert);

  /// Changes relative to the view: a document that becomes a [T] or starts passing the view's
  /// filters is added, and one that stops is removed.
  Stream<List<DocumentChangeSnapshotView<T>>> streamChanges() =>
      _query.streamChanges().map((changes) => [
            for (final change in changes)
              DocumentChangeSnapshotView<T>._(change),
          ]);

  ObservableQueryView<T> observe({bool multicast = false}) =>
      ObservableQueryView._(_query.observe(multicast: multicast),
          sortBy: _sortBy);

  QueryView<T> where(QueryViewFilterFn<T> filter) => QueryView._selected(
        _query.where((snap) => filter(DocumentSnapshotView<T>._(snap))),
        sortBy: _sortBy,
      );

  QueryView<T> sortBy(QueryViewSortByFn<T> sortBy) =>
      QueryView._selected(_query, sortBy: sortBy);
}

class ObservableQueryView<T> extends QueryView<T> {
  @override
  // ignore: overridden_fields
  final ObservableQuery _query;

  ObservableQueryView._(
    this._query, {
    super.sortBy,
  }) : super._selected(_query);

  bool get multicast => _query.multicast;
  void dispose() => _query.dispose();
}

class DocumentView<T> {
  final Document _doc;

  DocumentView(this._doc);

  String get id => _doc.id;
  String get path => _doc.path;

  DocumentSnapshotView<T>? get() => DocumentSnapshotView.of<T>(_doc.get());

  bool exists() => get() != null;

  Stream<DocumentSnapshotView<T>?> stream() => _doc
      .stream()
      .map(DocumentSnapshotView.of<T>)
      .distinct((prev, next) => prev == null && next == null);
}

class DocumentSnapshotView<T> {
  final DocumentSnapshot<Object?> _snap;

  DocumentSnapshotView._(this._snap);

  String get id => _snap.id;
  String get path => _snap.path;
  T get data => _snap.data as T;

  static DocumentSnapshotView<T>? of<T>(DocumentSnapshot? snap) {
    if (snap != null && snap.data is T) {
      return DocumentSnapshotView._(snap);
    }
    return null;
  }
}

class DocumentChangeSnapshotView<T> {
  final DocumentChangeSnapshot<Object?> _change;

  DocumentChangeSnapshotView._(this._change);

  String get id => _change.id;
  String get path => _change.path;
  BroadcastEvents get event => _change.event;
  T? get data => _change.data as T?;
  T? get prevData => _change.prevData as T?;
}
