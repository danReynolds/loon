part of loon;

abstract class Queryable<T> {
  Query<T> toQuery();
}

class Query<T> extends Queryable<T> {
  final Collection<T> collection;
  final List<FilterFn<T>> filters;
  final SortFn<T>? sort;

  Query(
    this.collection, {
    this.filters = const [],
    this.sort,
  });

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

  List<DocumentSnapshot<T>> get() {
    return _sortQuery(_filterQuery(collection.get()));
  }

  ObservableQuery<T> observe({
    bool multicast = false,
  }) {
    return ObservableQuery<T>(
      collection,
      filters: filters,
      sort: sort,
      multicast: multicast,
    );
  }

  bool exists() {
    return _filterQuery(collection.get()).isNotEmpty;
  }

  bool isScheduledForBroadcast() {
    return collection.isPendingBroadcast();
  }

  Stream<List<DocumentSnapshot<T>>> stream() {
    return observe().stream();
  }

  Stream<List<DocumentChangeSnapshot<T>>> streamChanges() {
    return observe().streamChanges();
  }

  Query<T> sortBy(SortFn<T> sort) {
    return Query<T>(
      this.collection,
      filters: filters,
      sort: sort,
    );
  }

  Query<T> where(FilterFn<T> filter) {
    return Query<T>(
      this.collection,
      filters: [...filters, filter],
      sort: sort,
    );
  }

  @override
  toQuery() {
    return this;
  }
}
