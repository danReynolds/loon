part of 'loon.dart';

/// A live, read-only selection of a collection's documents by data type.
///
/// Create one with [Collection.whereType]. Documents of other types are absent
/// from the view. Reads use the original collection's serialization and storage.
class CollectionView<T> extends _QueryView<T> implements StoreReference {
  final Collection<Object?> _collection;

  CollectionView._(this._collection)
      : super(_collection.where((snap) => snap.data is T));

  @override
  String get path => _collection.path;

  String get parent => _collection.parent;
  String get name => _collection.name;

  /// Returns a read-only handle. Missing documents and other subtypes read null.
  DocumentView<T> doc(String id) => _DocumentView<T>(_collection.doc(id));

  bool exists() => get().isNotEmpty;

  /// Narrows this view further, including subclasses of [S].
  CollectionView<S> whereType<S extends T>() =>
      CollectionView<S>._(_collection);
}
