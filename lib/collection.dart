part of loon;

class Collection<T> {
  final String parent;
  final String name;
  final FromJson<T>? fromJson;
  final ToJson<T>? toJson;
  final PersistorSettings? persistorSettings;

  /// Returns the set of documents that the document associated with the given
  /// [DocumentSnapshot] is dependent on.
  final DependenciesBuilder<T>? dependenciesBuilder;

  Collection(
    this.parent,
    this.name, {
    this.fromJson,
    this.toJson,
    this.persistorSettings,
    this.dependenciesBuilder,
  });

  String get path {
    if (parent == 'ROOT') {
      return name;
    }
    return "${parent}__$name";
  }

  @override
  bool operator ==(Object other) {
    if (identical(this, other)) {
      return true;
    }
    if (other is Collection) {
      return other.path == path;
    }
    return false;
  }

  @override
  int get hashCode => Object.hashAll([parent, name]);

  bool isPersistenceEnabled() {
    return persistorSettings?.persistenceEnabled ??
        Loon._instance._isGlobalPersistenceEnabled;
  }

  Document<T> doc(String id) {
    return Document<T>(
      path,
      id,
      fromJson: fromJson,
      toJson: toJson,
      persistorSettings: persistorSettings,
      dependenciesBuilder: dependenciesBuilder,
    );
  }

  void delete({
    bool broadcast = true,
  }) {
    Loon._instance._deleteCollection(
      this,
      broadcast: broadcast,
      persist: isPersistenceEnabled(),
    );
  }

  void replace(
    List<DocumentSnapshot<T>> snaps, {
    bool broadcast = true,
  }) {
    // Loon._instance._replaceCollection<T>(
    //   key,
    //   snaps: snaps,
    //   fromJson: fromJson,
    //   toJson: toJson,
    //   persistorSettings: persistorSettings,
    //   dependenciesBuilder: dependenciesBuilder,
    //   broadcast: broadcast,
    // );
  }

  List<DocumentSnapshot<T>> get() {
    return Loon._instance._getSnapshots(this);
  }

  bool exists() {
    return Loon._instance._documentStore.contains(path);
  }

  Stream<List<DocumentSnapshot<T>>> stream() {
    return Query<T>(this).observe().stream();
  }

  Stream<List<DocumentChangeSnapshot<T>>> streamChanges() {
    return Query<T>(this).observe().streamChanges();
  }

  Query<T> where(FilterFn<T> filter) {
    return Query<T>(this, filters: [filter]);
  }
}
