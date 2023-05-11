part of loon;

class Query<T> {
  final String collection;
  final FilterFn<T>? filter;
  final FromJson<T>? fromJson;
  final ToJson<T>? toJson;
  final PersistorSettings<T>? persistorSettings;

  Query(
    this.collection, {
    required this.filter,
    required this.fromJson,
    required this.toJson,
    required this.persistorSettings,
  });

  List<DocumentSnapshot<T>> _resolveQuery(List<Document<T>> docs) {
    final snaps =
        docs.map((doc) => doc.get()).whereType<DocumentSnapshot<T>>().toList();

    if (filter == null) {
      return snaps;
    }

    return snaps.where(filter!).toList();
  }

  List<DocumentSnapshot<T>> get() {
    return _resolveQuery(
      Loon.instance._getDocuments(
        collection,
        fromJson: fromJson,
        toJson: toJson,
        persistorSettings: persistorSettings,
      ),
    );
  }

  WatchQuery<T> watch() {
    return WatchQuery<T>(
      collection,
      filter: filter,
      fromJson: fromJson,
      toJson: toJson,
      persistorSettings: persistorSettings,
    );
  }
}
