part of 'loon.dart';

class CollectionView<T> extends QueryView<T> {
  CollectionView(super._query);

  DocumentView<T> doc(String id) => DocumentView(_query.collection.doc(id));
}

typedef QueryViewFilterFn<T> = bool Function(DocumentSnapshotView<T>);
typedef QueryViewSortByFn<T> = int Function(
    DocumentSnapshotView<T> a, DocumentSnapshotView<T> b);

class QueryView<T> {
  final Query _query;
  final List<QueryViewFilterFn<T>> _filters;
  final QueryViewSortByFn<T>? _sortBy;

  QueryView(
    this._query, {
    List<QueryViewFilterFn<T>>? filters,
    QueryViewSortByFn<T>? sortBy,
  })  : _filters = filters ?? [],
        _sortBy = sortBy;

  String get path => _query.path;

  List<DocumentSnapshotView<T>> _convert(List<DocumentSnapshot> snaps) => snaps
      .map(DocumentSnapshotView.of<T>)
      .whereType<DocumentSnapshotView<T>>()
      .where((snap) => _filters.every((filter) => filter(snap)))
      .toList();

  List<DocumentSnapshotView<T>> get() => _convert(_query.get());

  Stream<List<DocumentSnapshotView<T>>> stream() =>
      _query.stream().map(_convert);

  Stream<List<DocumentChangeSnapshotView<T>>> streamChanges() =>
      _query.streamChanges().map((changes) => changes
          .map(DocumentChangeSnapshotView.of<T>)
          .whereType<DocumentChangeSnapshotView<T>>()
          .toList());

  ObservableQueryView<T> observe({bool multicast = false}) =>
      ObservableQueryView._(_query.observe(multicast: multicast));

  QueryView<T> where(QueryViewFilterFn filter) => QueryView(_query,
      filters: [
        ..._filters,
        filter,
      ],
      sortBy: _sortBy);

  QueryView<T> sortBy(QueryViewSortByFn<T> sortBy) =>
      QueryView(_query, filters: _filters, sortBy: sortBy);
}

class ObservableQueryView<T> extends QueryView<T> {
  @override
  // ignore: overridden_fields
  final ObservableQuery _query;

  ObservableQueryView._(
    this._query, {
    super.filters,
    super.sortBy,
  }) : super(_query);

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

  /// The document's snapshots while its data is a [T], and a single null while it is missing or
  /// another type.
  Stream<DocumentSnapshotView<T>?> stream() =>
      _doc.stream().map(DocumentSnapshotView.of<T>);
}

class DocumentSnapshotView<T> {
  final DocumentSnapshot<Object?> _snap;

  DocumentSnapshotView._(this._snap);

  String get id => _snap.id;
  String get path => _snap.path;
  T get data => _snap.data as T;

  static DocumentSnapshotView<T>? of<T>(DocumentSnapshot? snap) {
    if (snap is DocumentSnapshot<T>) {
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

  static DocumentChangeSnapshotView<T>? of<T>(DocumentChangeSnapshot? change) {
    if (change is DocumentChangeSnapshot<T>) {
      return DocumentChangeSnapshotView._(change);
    }
    return null;
  }
}
