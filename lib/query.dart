part of loon;

class Query<T> {
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

  List<DocumentSnapshot<T>> _filterQuery(List<Document<T>> docs) {
    final snaps =
        docs.map((doc) => doc.get()).whereType<DocumentSnapshot<T>>().toList();

    if (filters.isEmpty) {
      return snaps;
    }

    return snaps.where((snap) {
      for (final filter in filters) {
        if (!filter(snap)) {
          return false;
        }
      }
      return true;
    }).toList();
  }

  List<DocumentSnapshot<T>> _sortQuery(List<DocumentSnapshot<T>> snaps) {
    if (sort == null) {
      return snaps;
    }
    snaps.sort(sort);
    return snaps;
  }

  List<DocumentSnapshot<T>> get() {
    return _sortQuery(
      _filterQuery(
        Loon._instance._getDocuments(
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

  Stream<List<DocumentSnapshot<T>>> stream() {
    return asObservable().stream();
  }

  Stream<BroadcastObservableChangeRecord<List<DocumentSnapshot<T>>>>
      streamChanges() {
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
