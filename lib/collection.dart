part of loon;

class Collection<T> extends Query<T> {
  Collection(
    super.collection, {
    required super.fromJson,
    required super.toJson,
    required super.persistorSettings,
  }) : super(filters: [], sort: null);

  Document<T> doc(String id) {
    return Document<T>(
      collection: collection,
      id: id,
      fromJson: fromJson,
      toJson: toJson,
      persistorSettings: persistorSettings,
    );
  }

  void clear() {
    Loon._instance._clearCollection(collection);
  }

  void replace(List<DocumentSnapshot<T>> snaps) {
    Loon._instance._replaceCollection<T>(
      collection,
      snaps: snaps,
      fromJson: fromJson,
      toJson: toJson,
      persistorSettings: persistorSettings,
    );
  }
}
