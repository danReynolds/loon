part of 'loon.dart';

/// A document's read API. Subtype views omit documents of other types.
abstract interface class DocumentView<T> implements StoreReference {
  String get id;
  String get parent;
  DocumentSnapshotView<T>? get();
  bool exists();
  ObservableDocumentView<T> observe({bool multicast = false});
  Stream<DocumentSnapshotView<T>?> stream();
  Stream<DocumentChangeSnapshotView<T>> streamChanges();
}

/// An observed document with an explicit lifetime and no mutation operations.
abstract interface class ObservableDocumentView<T> implements DocumentView<T> {
  bool get multicast;
  bool get isDirty;
  void dispose();
}

class _DocumentView<T> implements DocumentView<T> {
  final Document<Object?> _document;

  _DocumentView(this._document);

  @override
  String get id => _document.id;

  @override
  String get parent => _document.parent;

  @override
  String get path => _document.path;

  @override
  DocumentSnapshotView<T>? get() {
    final snap = _document.get();
    if (snap == null) return null;
    final data = snap.data;
    return data is T ? DocumentSnapshotView(doc: this, data: data) : null;
  }

  @override
  bool exists() => get() != null;

  @override
  ObservableDocumentView<T> observe({bool multicast = false}) =>
      _ObservableDocumentView(
        _document,
        _document._toQuery().where((snap) => snap.data is T).observe(
              multicast: multicast,
            ),
      );

  @override
  Stream<DocumentSnapshotView<T>?> stream() => observe().stream();

  @override
  Stream<DocumentChangeSnapshotView<T>> streamChanges() =>
      observe().streamChanges();

  @override
  bool operator ==(Object other) =>
      other is _DocumentView<T> &&
      other._viewType == T &&
      other._document == _document;

  Type get _viewType => T;

  @override
  int get hashCode => Object.hash(_document, T);
}

// A single-ID query gives document views the same membership transitions as
// collection views, without another observer or a scan of the collection.
class _ObservableDocumentView<T> extends _DocumentView<T>
    implements ObservableDocumentView<T> {
  final _ObservableQueryView<T> _view;

  _ObservableDocumentView(super.document, ObservableQuery<Object?> observer)
      : _view = _ObservableQueryView(observer);

  @override
  bool get multicast => _view.multicast;

  @override
  bool get isDirty => _view.isDirty;

  @override
  void dispose() => _view.dispose();

  @override
  ObservableDocumentView<T> observe({bool multicast = false}) => this;

  @override
  DocumentSnapshotView<T>? get() {
    final snaps = _view.get();
    return snaps.isEmpty ? null : snaps.single;
  }

  late final _stream =
      _view.stream().map((snaps) => snaps.isEmpty ? null : snaps.single);
  late final _changes = _view.streamChanges().expand((changes) => changes);

  @override
  Stream<DocumentSnapshotView<T>?> stream() => _stream;

  @override
  Stream<DocumentChangeSnapshotView<T>> streamChanges() => _changes;
}
