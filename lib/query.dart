part of loon;

class Query<T> implements Computable<List<DocumentSnapshot<T>>> {
  final String collection;
  final List<FilterFn<T>> filters;
  final SortFn<T>? sort;
  final FromJson<T>? fromJson;
  final ToJson<T>? toJson;
  final PersistorSettings<T>? persistorSettings;

  Query(
    this.collection, {
    required this.filters,
    required this.sort,
    required this.fromJson,
    required this.toJson,
    required this.persistorSettings,
  });

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
    return _sortQuery(
      _filterQuery(
        Loon._instance._getSnapshots(
          collection,
          fromJson: fromJson,
          toJson: toJson,
          persistorSettings: persistorSettings,
        ),
      ),
    );
  }

  ObservableQuery<T> asObservable() {
    return ObservableQuery<T>(
      collection,
      filters: filters,
      sort: sort,
      fromJson: fromJson,
      toJson: toJson,
      persistorSettings: persistorSettings,
    );
  }

  @override
  Stream<List<DocumentSnapshot<T>>> stream() {
    return asObservable().stream();
  }

  Stream<ObservableChangeRecord<List<DocumentSnapshot<T>>>> streamChanges() {
    return asObservable().streamChanges();
  }

  Query<T> sortBy(SortFn<T> sort) {
    return Query<T>(
      collection,
      filters: filters,
      sort: sort,
      fromJson: fromJson,
      toJson: toJson,
      persistorSettings: persistorSettings,
    );
  }

  Query<T> where(FilterFn<T> filter) {
    return Query<T>(
      collection,
      filters: [...filters, filter],
      sort: sort,
      fromJson: fromJson,
      toJson: toJson,
      persistorSettings: persistorSettings,
    );
  }
}
