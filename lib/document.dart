part of 'loon.dart';

class Document<T> implements StoreReference {
  final String id;
  final String parent;
  final FromJson<T>? fromJson;
  final ToJson<T>? toJson;
  final DependenciesBuilder<T>? dependenciesBuilder;

  late final PathPersistorSettings? persistorSettings;

  Document(
    this.parent,
    this.id, {
    this.fromJson,
    this.toJson,
    this.dependenciesBuilder,
    PersistorSettings? persistorSettings,
  }) {
    this.persistorSettings = switch (persistorSettings) {
      PathPersistorSettings _ => persistorSettings,
      // If the persistor settings are not yet associated with a path, then the settings
      // are updated to having been applied at the document's path.
      PersistorSettings _ =>
        PathPersistorSettings(settings: persistorSettings, ref: this),
      _ => persistorSettings,
    };
  }

  static Document<S> fromPath<S>(
    String path, {
    FromJson<S>? fromJson,
    ToJson<S>? toJson,
    PersistorSettings? persistorSettings,
    DependenciesBuilder<S>? dependenciesBuilder,
  }) {
    final [...pathSegments, id] = path.split(_BaseValueStore.delimiter);
    return Document<S>(
      pathSegments.join(_BaseValueStore.delimiter),
      id,
      fromJson: fromJson,
      toJson: toJson,
      persistorSettings: persistorSettings,
      dependenciesBuilder: dependenciesBuilder,
    );
  }

  @override
  bool operator ==(Object other) {
    if (identical(this, other)) {
      return true;
    }

    // Documents are equivalent based on their path. An [ObservableDocument] is equal to the
    // document it observes; observer instances are tracked by identity in the [BroadcastManager].
    return other is Document && other.path == path;
  }

  @override
  int get hashCode => Object.hashAll([parent, id]);

  @override
  String get path {
    if (id.isEmpty) {
      return parent;
    }

    return "${parent}__$id";
  }

  Collection<S> subcollection<S>(
    String name, {
    FromJson<S>? fromJson,
    ToJson<S>? toJson,
    PersistorSettings? persistorSettings,
    DependenciesBuilder<S>? dependenciesBuilder,
  }) {
    return Collection<S>(
      path,
      name,
      fromJson: fromJson,
      toJson: toJson,
      persistorSettings: persistorSettings ?? this.persistorSettings,
      dependenciesBuilder: dependenciesBuilder,
    );
  }

  DocumentSnapshot<T> create(
    T data, {
    bool broadcast = true,
    bool persist = true,
  }) {
    if (exists()) {
      throw Exception('Cannot create duplicate document');
    }

    return Loon._instance.writeDocument<T>(
      this,
      data,
      broadcast: broadcast,
      persist: persist,
      event: BroadcastEvents.added,
    );
  }

  DocumentSnapshot<T> update(
    T data, {
    bool? broadcast,
    bool persist = true,
  }) {
    if (!exists()) {
      throw Exception('Missing document $path');
    }

    return Loon._instance.writeDocument<T>(
      this,
      data,
      // As an optimization, broadcasting is skipped when updating a document if its
      // data is unchanged.
      //
      // The document store is accessed directly here instead of going through the public [Document.get]
      // API since [get] checks for type compatibility of the existing value with the current document
      // and the update may be altering the type of the document.
      broadcast:
          broadcast ?? Loon._instance.documentStore.get(path)?.data != data,
      persist: persist,
      event: BroadcastEvents.modified,
    );
  }

  DocumentSnapshot<T> createOrUpdate(
    T data, {
    bool? broadcast,
    bool persist = true,
  }) {
    if (exists()) {
      return update(
        data,
        broadcast: broadcast,
        persist: persist,
      );
    }
    return create(data, broadcast: broadcast ?? true, persist: persist);
  }

  DocumentSnapshot<T> modify(
    ModifyFn<T> modifyFn, {
    bool? broadcast,
    bool persist = true,
  }) {
    final value = get();
    if (value is! DocumentSnapshot<T>) {
      throw Exception('Missing document $path');
    }

    return createOrUpdate(
      modifyFn(value),
      broadcast: broadcast,
      persist: persist,
    );
  }

  void delete() {
    Loon._instance.deleteDocument<T>(this);
  }

  DocumentSnapshot<T>? get() {
    return Loon._instance.getSnapshot(this);
  }

  ObservableDocument<T> observe({
    bool multicast = false,
  }) {
    return ObservableDocument<T>(
      parent,
      id,
      fromJson: fromJson,
      toJson: toJson,
      persistorSettings: persistorSettings,
      multicast: multicast,
      dependenciesBuilder: dependenciesBuilder,
    );
  }

  Stream<DocumentSnapshot<T>?> stream() {
    return observe().stream();
  }

  Stream<DocumentChangeSnapshot<T>> streamChanges() {
    return observe().streamChanges();
  }

  bool exists() {
    return Loon._instance.existsSnap(this);
  }

  Set<Document>? dependencies() {
    return Loon._instance.dependencyManager.getDependencies(this);
  }

  Set<Document>? dependents() {
    return Loon._instance.dependencyManager.getDependents(this);
  }

  bool isPersistenceEnabled() {
    return persistorSettings?.enabled ??
        Loon._instance._isGlobalPersistenceEnabled;
  }

  bool get encrypted {
    return persistorSettings?.encrypted ??
        Loon.persistorSettings?.encrypted ??
        false;
  }

  /// Returns the serialized document data.
  dynamic getSerialized() {
    final data = get()?.data;
    final toJson = this.toJson;

    // If the document has a [toJson] serializer, then it should return the
    // serialized [Json] data.
    if (data != null && toJson != null) {
      return toJson(data);
    }
    return data;
  }

  /// Rebroadcasts the document as a [BroadcastEvents.touched] event. Used when document or query
  /// observers should re-evaluate the document without rewriting or persisting its value.
  /// Rebroadcasting a document that does not exist does nothing.
  void rebroadcast() {
    // There is no value for observers to re-evaluate, and scheduling a touched event would
    // needlessly invalidate the cached values of every query on the collection.
    if (!exists()) {
      return;
    }

    Loon._instance.broadcastManager
        .writeDocument(this, BroadcastEvents.touched);
  }

  /// Rebuild the document's dependencies with the [dependenciesBuilder].
  void rebuildDependencies() {
    final snap = get();
    if (snap == null) {
      return;
    }

    Loon._instance.dependencyManager.updateDependencies(snap);
  }
}
