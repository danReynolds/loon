part of loon;

class Collection<T> extends Query<T> {
  Collection(
    super.collection, {
    required super.fromJson,
    required super.toJson,
    required super.persistorSettings,
  }) : super(filter: null);

  Document<T> doc(String id) {
    return Document<T>(
      collection: collection,
      id: id,
      fromJson: fromJson,
      toJson: toJson,
      persistorSettings: persistorSettings,
    );
  }

  void delete(String id) {
    Loon.instance._deleteDocument<T>(doc(id));
  }

  Query<T> where(FilterFn<T> filter) {
    return Query<T>(
      collection,
      filter: filter,
      fromJson: fromJson,
      toJson: toJson,
      persistorSettings: persistorSettings,
    );
  }
}
