part of 'loon.dart';

abstract class Queryable<T> {
  Query<T> toQuery();
}

class Query<T> extends QueryView<T> implements Queryable<T> {
  final Collection<T> collection;
  final List<FilterFn<T>> filters;
  final SortFn<T>? sort;
  final Document<T>? _document;

  Query(
    this.collection, {
    this.filters = const [],
    this.sort,
  }) : _document = null;

  Query._(
    this.collection,
    this._document, {
    this.filters = const [],
    this.sort,
  });

  factory Query._forDocument(Document<T> doc) => Query._(
        Collection.fromPath<T>(
          doc.parent,
          fromJson: doc.fromJson,
          toJson: doc.toJson,
          persistorSettings: doc.persistorSettings,
          dependenciesBuilder: doc.dependenciesBuilder,
        ),
        doc,
      );

  @override
  String get path {
    return collection.path;
  }

  bool _filter(DocumentSnapshot<T> snap) {
    for (final filter in filters) {
      if (!filter(snap)) {
        return false;
      }
    }
    return true;
  }

  List<DocumentSnapshot<T>> _filterQuery(List<DocumentSnapshot<T>> snaps) {
    return snaps.where(_filter).toList();
  }

  List<DocumentSnapshot<T>> _sortQuery(List<DocumentSnapshot<T>> snaps) {
    if (sort == null) {
      return snaps;
    }
    snaps.sort(sort);
    return snaps;
  }

  @override
  List<DocumentSnapshot<T>> get() {
    final document = _document;
    if (document != null) {
      final snap = document.get();
      return snap != null && _filter(snap) ? [snap] : [];
    }
    return _sortQuery(_filterQuery(collection.get()));
  }

  @override
  ObservableQuery<T> observe({
    bool multicast = false,
  }) {
    return ObservableQuery<T>._(this, multicast: multicast);
  }

  @override
  Stream<List<DocumentSnapshot<T>>> stream() {
    return observe().stream();
  }

  @override
  Stream<List<DocumentChangeSnapshot<T>>> streamChanges() {
    return observe().streamChanges();
  }

  @override
  Query<T> sortBy(SortFn<T> sort) {
    return Query<T>._(
      collection,
      _document,
      filters: filters,
      sort: sort,
    );
  }

  @override
  Query<T> where(FilterFn<T> filter) {
    return Query<T>._(
      collection,
      _document,
      filters: [...filters, filter],
      sort: sort,
    );
  }

  @override
  toQuery() {
    return this;
  }
}
