part of 'loon.dart';

class DocumentSnapshotView<S extends T, T> {
  final DocumentSnapshot<T> _snap;

  DocumentSnapshotView(this._snap);

  S? get data {
    if (_snap.data case S data) {
      return data;
    }

    return null;
  }
}

class DocumentView<S extends T, T> {
  final Document<T> doc;

  DocumentView(this.doc);

  DocumentSnapshotView<S, T>? get() {
    final snap = doc.get();
    if (snap == null) {
      return null;
    }
    return DocumentSnapshotView(snap);
  }

  Stream<DocumentSnapshotView<S, T>?> stream() {
    return doc
        .stream()
        .map((snap) => snap == null ? null : DocumentSnapshotView(snap));
  }
}

/// A view of a collection that allows for type-safe narrowing to a specific subtype of the collection's document type.
class CollectionView<S extends T, T> {
  final Collection<T> _collection;

  CollectionView(this._collection);

  DocumentView<S, T> doc(String id) {
    return DocumentView(_collection.doc(id));
  }

  List<DocumentSnapshotView<S, T>> get() {
    return _collection
        .get()
        .map((snap) => DocumentSnapshotView<S, T>(snap))
        .toList();
  }

  Stream<List<DocumentSnapshotView<S, T>>> stream() {
    return _collection.stream().map((snaps) =>
        snaps.map((snap) => DocumentSnapshotView<S, T>(snap)).toList());
  }
}
