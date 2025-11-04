part of 'loon.dart';

const _rootKey = 'root';

class _RootCollection extends StoreReference {
  const _RootCollection();

  @override
  final String path = _rootKey;
}

class Collection<T> implements Queryable<T>, StoreReference {
  final String parent;
  final String name;
  final FromJson<T>? fromJson;
  final ToJson<T>? toJson;
  late final PersistorSettings? persistorSettings;

  /// Returns the set of documents that the document associated with the given
  /// [DocumentSnapshot] is dependent on.
  final DependenciesBuilder<T>? dependenciesBuilder;

  static const root = _RootCollection();

  Collection(
    this.parent,
    this.name, {
    this.fromJson,
    this.toJson,
    this.dependenciesBuilder,
    PersistorSettings? persistorSettings,
  }) {
    this.persistorSettings = switch (persistorSettings) {
      PathPersistorSettings _ => persistorSettings,
      // If the persistor settings are not yet associated with a path, then if a value key
      // is provided, then the settings are updated to having been applied at the collection's path.
      PersistorSettings(key: final PersistorValueKey _) =>
        PathPersistorSettings(settings: persistorSettings, ref: this),
      _ => persistorSettings,
    };
  }

  static Collection<S> fromPath<S>(
    String path, {
    FromJson<S>? fromJson,
    ToJson<S>? toJson,
    PersistorSettings? persistorSettings,
    DependenciesBuilder<S>? dependenciesBuilder,
  }) {
    final [...pathSegments, id] = path.split(_BaseValueStore.delimiter);

    return Collection<S>(
      pathSegments.join(_BaseValueStore.delimiter),
      id,
      fromJson: fromJson,
      toJson: toJson,
      persistorSettings: persistorSettings,
      dependenciesBuilder: dependenciesBuilder,
    );
  }

  @override
  String get path {
    if (parent.isEmpty || parent == _rootKey) {
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

  Document<T> doc([String? id]) {
    return Document<T>(
      path,
      id ?? generateId(),
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

  ObservableQuery<T> observe({
    bool multicast = false,
  }) {
    return toQuery().observe(multicast: multicast);
  }

  @override
  Query<T> toQuery() {
    return Query(this);
  }
}
