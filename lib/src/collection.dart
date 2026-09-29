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

  /// The collection this handle was narrowed from by [whereType]. It owns the stored
  /// snapshots and their serialization; this handle reads only the documents whose data is [T].
  final Collection<Object?>? _source;

  static const root = _RootCollection();

  /// Creates a collection at the top level (empty [parent]) or under a document
  /// [parent] path. The [name] must be nonempty, contain no `__`, and not end with
  /// `_`. These rules are checked with assertions.
  Collection(
    this.parent,
    this.name, {
    this.fromJson,
    this.toJson,
    this.dependenciesBuilder,
    PersistorSettings? persistorSettings,
  })  : _source = null,
        assert(parent.isEmpty || _isValidDocumentPath(parent),
            'Collection parent must be empty or a valid document path'),
        assert(_isValidReferenceSegment(name),
            'Collection name must be nonempty, contain no "__", and not end with "_"') {
    this.persistorSettings = switch (persistorSettings) {
      PathPersistorSettings _ => persistorSettings,
      // If the persistor settings are not yet associated with a path, then if a value key
      // is provided, then the settings are updated to having been applied at the collection's path.
      PersistorSettings(key: final PersistorValueKey _) =>
        PathPersistorSettings(settings: persistorSettings, ref: this),
      _ => persistorSettings,
    };
  }

  Collection._narrowed(
    Collection<Object?> source, {
    this.toJson,
    this.dependenciesBuilder,
  })  : parent = source.parent,
        name = source.name,
        fromJson = null,
        _source = source {
    persistorSettings = source.persistorSettings;
  }

  static Collection<S> fromPath<S>(
    String path, {
    FromJson<S>? fromJson,
    ToJson<S>? toJson,
    PersistorSettings? persistorSettings,
    DependenciesBuilder<S>? dependenciesBuilder,
  }) {
    assert(_isValidCollectionPath(path), 'Expected a valid collection path');
    final (parent, id) = splitReferencePath(path);

    return Collection<S>(
      parent,
      id,
      fromJson: fromJson,
      toJson: toJson,
      persistorSettings: persistorSettings,
      dependenciesBuilder: dependenciesBuilder,
    );
  }

  @override
  late final String path = parent.isEmpty ? name : '${parent}__$name';

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
  int get hashCode => Object.hash(parent, name);

  bool isPersistenceEnabled() {
    return persistorSettings?.enabled ??
        Loon._instance._isGlobalPersistenceEnabled;
  }

  /// Returns this collection narrowed to the documents whose data is [S], including
  /// subclasses of [S]. The narrowed collection shares this collection's storage and
  /// serialization, so documents of other types are absent from its reads, queries and
  /// streams, and its writes only affect documents of type [S].
  Collection<S> whereType<S extends T>() {
    return Collection<S>._narrowed(
      _source ?? this,
      toJson: toJson,
      dependenciesBuilder: dependenciesBuilder,
    );
  }

  Document<T> doc([String? id]) {
    final source = _source;
    if (source != null) {
      return Document<T>._narrowed(
        source.doc(id),
        toJson: toJson,
        dependenciesBuilder: dependenciesBuilder,
      );
    }

    return Document<T>(
      path,
      id ?? generateSecureId(),
      fromJson: fromJson,
      toJson: toJson,
      persistorSettings: persistorSettings,
      dependenciesBuilder: dependenciesBuilder,
    );
  }

  /// Deletes the collection. A narrowed collection deletes only its documents.
  void delete() {
    if (_source != null) {
      for (final snap in get()) {
        snap.doc.delete();
      }
      return;
    }

    Loon._instance.deleteCollection(this);
  }

  /// Replaces the collection's documents with [snaps]. A narrowed collection replaces
  /// only its documents, and throws if a replacement ID belongs to a document of another type.
  void replace(List<DocumentSnapshot<T>> snaps) {
    final source = _source;
    if (source != null) {
      for (final snap in snaps) {
        if (source.doc(snap.id).exists() && !doc(snap.id).exists()) {
          throw Exception('Cannot replace document ${snap.path} of another type');
        }
      }
      delete();
      for (final snap in snaps) {
        doc(snap.id).create(snap.data);
      }
      return;
    }

    Loon._instance.replaceCollection<T>(
      this,
      snaps,
    );
  }

  List<DocumentSnapshot<T>> get() {
    final source = _source;
    if (source == null) {
      return Loon._instance.getSnapshots(this);
    }

    // Handles come from the source rather than the stored snapshots, so that they read and
    // write with the source's serialization.
    return [
      for (final snap in source.get())
        if (snap.data case final T data)
          DocumentSnapshot(doc: doc(snap.id), data: data),
    ];
  }

  bool exists() {
    final source = _source;
    if (source != null) {
      return source.get().any((snap) => snap.data is T);
    }

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
