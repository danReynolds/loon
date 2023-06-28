part of loon;

class Query<T> {
  final String collection;
  final FilterFn<T>? filter;
  final SortFn<T>? sort;
  final FromJson<T>? fromJson;
  final ToJson<T>? toJson;
  final PersistorSettings<T>? persistorSettings;

  Query(
    this.collection, {
    required this.filter,
    required this.sort,
    required this.fromJson,
    required this.toJson,
    required this.persistorSettings,
  });

  List<DocumentSnapshot<T>> _resolveQuery(List<Document<T>> docs) {
    final snaps =
        docs.map((doc) => doc.get()).whereType<DocumentSnapshot<T>>().toList();

    if (sort != null) {
      snaps.sort(sort);
    }

    if (filter == null) {
      return snaps;
    }

    return snaps.where(filter!).toList();
  }

  List<DocumentSnapshot<T>> get() {
    return _resolveQuery(
      Loon._instance._getDocuments(
        collection,
        fromJson: fromJson,
        toJson: toJson,
        persistorSettings: persistorSettings,
      ),
    );
  }

  ObservableQuery<T> asObservable() {
    return ObservableQuery<T>(
      collection,
      filter: filter,
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
}
