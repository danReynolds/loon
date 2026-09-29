part of 'loon.dart';

/// The read operations shared by ordinary queries and subtype views.
abstract class QueryView<T> extends Queryable<T> {
  List<DocumentSnapshotView<T>> get();

  QueryView<T> where(bool Function(DocumentSnapshotView<T> snap) filter);

  QueryView<T> sortBy(
    int Function(DocumentSnapshotView<T> a, DocumentSnapshotView<T> b) sort,
  );

  ObservableQueryView<T> observe({bool multicast = false});

  Stream<List<DocumentSnapshotView<T>>> stream() => observe().stream();

  Stream<List<DocumentChangeSnapshotView<T>>> streamChanges() =>
      observe().streamChanges();

  @override
  QueryView<T> toQuery() => this;
}

/// An observed query with an explicit lifetime, shared by queries and views.
abstract interface class ObservableQueryView<T> implements QueryView<T> {
  bool get multicast;
  bool get isDirty;
  void dispose();
}

// Keep the parent's query and runtime type intact. Its existing engine owns
// filtering, sorting, hydration, membership changes, and observer caching.
class _QueryView<T> extends QueryView<T> {
  final Query<Object?> _query;

  _QueryView(this._query);

  DocumentSnapshotView<T> _snapshot(DocumentSnapshot<Object?> snap) =>
      DocumentSnapshotView(
          doc: _DocumentView<T>(_query.collection.doc(snap.id)),
          data: snap.data as T);

  DocumentChangeSnapshotView<T> _change(
    DocumentChangeSnapshot<Object?> snap,
  ) =>
      DocumentChangeSnapshotView(
        doc: _DocumentView<T>(_query.collection.doc(snap.id)),
        data: snap.data as T?,
        prevData: snap.prevData as T?,
        event: snap.event,
      );

  @override
  List<DocumentSnapshotView<T>> get() => _query.get().map(_snapshot).toList();

  @override
  QueryView<T> where(bool Function(DocumentSnapshotView<T> snap) filter) =>
      _QueryView(_query.where((snap) => filter(_snapshot(snap))));

  @override
  QueryView<T> sortBy(
    int Function(DocumentSnapshotView<T> a, DocumentSnapshotView<T> b) sort,
  ) =>
      _QueryView(_query.sortBy((a, b) => sort(_snapshot(a), _snapshot(b))));

  @override
  ObservableQueryView<T> observe({bool multicast = false}) =>
      _ObservableQueryView(_query.observe(multicast: multicast));
}

class _ObservableQueryView<T> extends _QueryView<T>
    implements ObservableQueryView<T> {
  final ObservableQuery<Object?> _observer;

  _ObservableQueryView(this._observer) : super(_observer);

  @override
  bool get multicast => _observer.multicast;

  @override
  bool get isDirty => _observer.isDirty;

  @override
  void dispose() => _observer.dispose();

  @override
  ObservableQueryView<T> observe({bool multicast = false}) => this;

  late final _stream =
      _observer.stream().map((snaps) => snaps.map(_snapshot).toList());
  late final _changes =
      _observer.streamChanges().map((snaps) => snaps.map(_change).toList());

  @override
  Stream<List<DocumentSnapshotView<T>>> stream() => _stream;

  @override
  Stream<List<DocumentChangeSnapshotView<T>>> streamChanges() => _changes;
}
