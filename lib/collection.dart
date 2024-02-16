part of loon;

class Collection<T> extends Query<T> {
  Collection(
    super.name, {
    required super.fromJson,
    required super.toJson,
    required super.persistorSettings,
    required super.dependenciesBuilder,
  }) : super(filters: [], sort: null);

  Document<T> doc(String id) {
    return Document<T>(
      collection: name,
      id: id,
      fromJson: fromJson,
      toJson: toJson,
      persistorSettings: persistorSettings,
      dependenciesBuilder: dependenciesBuilder,
    );
  }

  bool isPersistenceEnabled() {
    return persistorSettings?.persistenceEnabled ??
        Loon._instance._isGlobalPersistenceEnabled;
  }

  void delete({
    bool broadcast = true,
  }) {
    Loon._instance._deleteCollection(
      name,
      broadcast: broadcast,
      persist: isPersistenceEnabled(),
    );
  }

  void replace(List<DocumentSnapshot<T>> snaps) {
    Loon._instance._replaceCollection<T>(
      name,
      snaps: snaps,
      fromJson: fromJson,
      toJson: toJson,
      persistorSettings: persistorSettings,
    );
  }
}
