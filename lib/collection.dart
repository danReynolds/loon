part of loon;

class Collection<T> implements Queryable<T>, StoreReference {
  final String parent;
  final String name;
  final FromJson<T>? fromJson;
  final ToJson<T>? toJson;
  final PersistorSettings<T>? persistorSettings;

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

  @override
  String get path {
    if (parent == _rootKey) {
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
    return persistorSettings?.enabled ??
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

  void delete() {
    Loon._instance.deleteCollection(this);
  }

  void replace(List<DocumentSnapshot<T>> snaps) {
    Loon._instance.replaceCollection<T>(
      this,
      snaps,
    );
  }

  List<DocumentSnapshot<T>> get() {
    return Loon._instance.getSnapshots(this);
  }

  bool exists() {
    return Loon._instance.documentStore.hasChildValues(path);
  }

  /// A collection is pending broadcast if the collection itself has any pending events
  /// or if any of its documents have any events.
  bool isPendingBroadcast() {
    return Loon._instance.broadcastManager.store.hasValue(path) ||
        Loon._instance.broadcastManager.store.hasChildValues(path);
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

  Query<T> sortBy(SortFn<T> sort) {
    return Query<T>(this, sort: sort);
  }

  @override
  Query<T> toQuery() {
    return Query(this);
  }
}
