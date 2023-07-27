part of loon;

class Collection<T> extends Query<T> {
  Collection(
    super.path, {
    required super.fromJson,
    required super.toJson,
    required super.persistorSettings,
  }) : super(filters: [], sort: null);

  Document<T> doc(String id) {
    return Document<T>(
      id: id,
      path: path,
      fromJson: fromJson,
      toJson: toJson,
      persistorSettings: persistorSettings,
    );
  }

  void clear() {
    Loon._instance._clearCollection(path);
  }
}
