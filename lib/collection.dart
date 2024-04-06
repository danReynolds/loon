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
      collection: key,
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

  bool exists() {
    return Loon._instance._hasCollection(key);
  }

  void delete({
    bool broadcast = true,
  }) {
    Loon._instance._deleteCollection(
      key,
      broadcast: broadcast,
      persist: isPersistenceEnabled(),
    );
  }

  void replace(
    List<DocumentSnapshot<T>> snaps, {
    bool broadcast = true,
  }) {
    Loon._instance._replaceCollection<T>(
      key,
      snaps: snaps,
      fromJson: fromJson,
      toJson: toJson,
      persistorSettings: persistorSettings,
      dependenciesBuilder: dependenciesBuilder,
      broadcast: broadcast,
    );
  }
}
