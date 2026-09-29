part of 'loon.dart';

/// The read operations shared by ordinary queries and subtype views.
abstract class QueryView<T> extends Queryable<T> {
  String get path;

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

  // Each write creates a new stored snapshot. Weak keys let derived queries
  // share its typed projection without retaining replaced/deleted snapshots.
  final Expando<DocumentSnapshotView<T>> _snapshots;

  _QueryView(this._query, [Expando<DocumentSnapshotView<T>>? snapshots])
      : _snapshots = snapshots ?? Expando();

  @override
  String get path => _query.path;

  DocumentSnapshotView<T> _snapshot(DocumentSnapshot<Object?> snap) =>
      _snapshots[snap] ??= DocumentSnapshotView(
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
      _QueryView(_query.where((snap) => filter(_snapshot(snap))), _snapshots);

  @override
  QueryView<T> sortBy(
    int Function(DocumentSnapshotView<T> a, DocumentSnapshotView<T> b) sort,
  ) =>
      _QueryView(_query.sortBy((a, b) => sort(_snapshot(a), _snapshot(b))),
          _snapshots);

  @override
  ObservableQueryView<T> observe({bool multicast = false}) =>
      _ObservableQueryView(_query.observe(multicast: multicast), _snapshots);
}

class _ObservableQueryView<T> extends _QueryView<T>
    implements ObservableQueryView<T> {
  final ObservableQuery<Object?> _observer;

  _ObservableQueryView(this._observer,
      [Expando<DocumentSnapshotView<T>>? snapshots])
      : super(_observer, snapshots);

  // The underlying observer replaces its result list when invalidated. Reuse
  // the projection for reads/listeners of that same list, without another cache
  // invalidation or disposal protocol.
  final _results = Expando<List<DocumentSnapshotView<T>>>();

  List<DocumentSnapshotView<T>> _project(
          List<DocumentSnapshot<Object?>> snaps) =>
      _results[snaps] ??= List.unmodifiable(snaps.map(_snapshot));

  @override
  List<DocumentSnapshotView<T>> get() => _project(_observer.get());

  @override
  bool get multicast => _observer.multicast;

  @override
  bool get isDirty => _observer.isDirty;

  @override
  void dispose() => _observer.dispose();

  @override
  ObservableQueryView<T> observe({bool multicast = false}) => this;

  late final _stream = _observer.stream().map(_project);
  late final _changes =
      _observer.streamChanges().map((snaps) => snaps.map(_change).toList());

  @override
  Stream<List<DocumentSnapshotView<T>>> stream() => _stream;

  @override
  Stream<List<DocumentChangeSnapshotView<T>>> streamChanges() => _changes;
}
