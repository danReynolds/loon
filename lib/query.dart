part of loon;

class Query<T> {
  final String name;
  final List<FilterFn<T>> filters;
  final SortFn<T>? sort;
  final FromJson<T>? fromJson;
  final ToJson<T>? toJson;
  final PersistorSettings? persistorSettings;

  /// Returns the set of documents that the document associated with the given
  /// [DocumentSnapshot] is dependent on.
  final DependenciesBuilder<T>? dependenciesBuilder;

  Query(
    this.name, {
    required this.filters,
    required this.sort,
    required this.fromJson,
    required this.toJson,
    required this.persistorSettings,
    required this.dependenciesBuilder,
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

  List<DocumentSnapshot<T>> get() {
    return _sortQuery(
      _filterQuery(
        Loon._instance._getSnapshots(
          name,
          fromJson: fromJson,
          toJson: toJson,
          persistorSettings: persistorSettings,
        ),
      ),
    );
  }

  ObservableQuery<T> observe({
    bool multicast = false,
  }) {
    return ObservableQuery<T>(
      name,
      filters: filters,
      sort: sort,
      fromJson: fromJson,
      toJson: toJson,
      persistorSettings: persistorSettings,
      dependenciesBuilder: dependenciesBuilder,
      multicast: multicast,
    );
  }

  Stream<List<DocumentSnapshot<T>>> stream() {
    return observe().stream();
  }

  Stream<List<DocumentChangeSnapshot<T>>> streamChanges() {
    return observe().streamChanges();
  }

  Query<T> sortBy(SortFn<T> sort) {
    return Query<T>(
      name,
      filters: filters,
      sort: sort,
      fromJson: fromJson,
      toJson: toJson,
      persistorSettings: persistorSettings,
      dependenciesBuilder: dependenciesBuilder,
    );
  }

  Query<T> where(FilterFn<T> filter) {
    return Query<T>(
      name,
      filters: [...filters, filter],
      sort: sort,
      fromJson: fromJson,
      toJson: toJson,
      persistorSettings: persistorSettings,
      dependenciesBuilder: dependenciesBuilder,
    );
  }
}
