part of 'loon.dart';

/// A live, read-only selection of a collection's documents by data type.
///
/// Create one with [Collection.view]. Documents of other types are absent
/// from the view. Reads use the original collection's serialization and storage.
class CollectionView<T> extends _QueryView<T> implements StoreReference {
  final Collection<Object?> _collection;

  CollectionView._(Collection<Object?> collection)
      : _collection = collection,
        super(collection.where((snap) => snap.data is T));

  @override
  String get path => _collection.path;

  String get parent => _collection.parent;
  String get name => _collection.name;

  /// Returns a read-only handle. Missing documents and other subtypes read null.
  DocumentView<T> doc(String id) => _DocumentView<T>(_collection.doc(id));

  bool exists() => _collection.get().any((snap) => snap.data is T);

  /// Narrows this view further, including subclasses of [S].
  CollectionView<S> view<S extends T>() => CollectionView<S>._(_collection);

  // Views of the same type over the same collection select the same documents, so a view
  // created again on every build compares equal and is not observed again.
  @override
  bool operator ==(Object other) =>
      other is CollectionView<T> && other._viewType == T && other.path == path;

  Type get _viewType => T;

  @override
  int get hashCode => Object.hash(path, T);
}
