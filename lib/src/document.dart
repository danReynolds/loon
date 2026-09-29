part of 'loon.dart';

class Document<T> implements StoreReference {
  final String id;
  final String parent;
  final FromJson<T>? fromJson;
  final ToJson<T>? toJson;
  final DependenciesBuilder<T>? dependenciesBuilder;

  late final PathPersistorSettings? persistorSettings;

  /// The document this handle was narrowed from by [Collection.whereType]. It owns the stored
  /// snapshot and its serialization; this handle reads the document only while its data is [T].
  final Document<Object?>? _source;

  /// Creates a document under a collection [parent] path. The [id] must be
  /// nonempty, contain no `__`, and not end with `_`. These rules are checked
  /// with assertions.
  Document(
    this.parent,
    this.id, {
    this.fromJson,
    this.toJson,
    this.dependenciesBuilder,
    PersistorSettings? persistorSettings,
  })  : _source = null,
        assert(_isValidCollectionPath(parent),
            'Document parent must be a valid collection path'),
        assert(_isValidReferenceSegment(id),
            'Document ID must be nonempty, contain no "__", and not end with "_"') {
    this.persistorSettings = switch (persistorSettings) {
      PathPersistorSettings _ => persistorSettings,
      // If the persistor settings are not yet associated with a path, then the settings
      // are updated to having been applied at the document's path.
      PersistorSettings _ =>
        PathPersistorSettings(settings: persistorSettings, ref: this),
      _ => persistorSettings,
    };
  }

  Document._narrowed(
    Document<Object?> source, {
    this.toJson,
    this.dependenciesBuilder,
  })  : parent = source.parent,
        id = source.id,
        fromJson = null,
        _source = source._source ?? source {
    persistorSettings = source.persistorSettings;
  }

  static Document<S> fromPath<S>(
    String path, {
    FromJson<S>? fromJson,
    ToJson<S>? toJson,
    PersistorSettings? persistorSettings,
    DependenciesBuilder<S>? dependenciesBuilder,
  }) {
    assert(_isValidDocumentPath(path), 'Expected a valid document path');
    final (parent, id) = splitReferencePath(path);
    return Document<S>(
      parent,
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
  late final int hashCode = Object.hash(parent, id);

  @override
  late final String path = '${parent}__$id';

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
    final source = _source;
    if (source != null) {
      // The source rejects an ID that is taken by a document of any type.
      source.create(data, broadcast: broadcast, persist: persist);
      return DocumentSnapshot(doc: this, data: data);
    }

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
    final source = _source;
    if (source != null) {
      // A narrowed document only updates a document of its type. Changing a document's type is
      // a write through the collection that owns it.
      if (!exists()) {
        throw Exception('Missing document $path');
      }
      source.update(data, broadcast: broadcast, persist: persist);
      return DocumentSnapshot(doc: this, data: data);
    }

    // The document store is accessed directly here instead of going through the public [Document.get]
    // API since [get] checks for type compatibility of the existing value with the current document
    // and the update may be altering the type of the document.
    final prevSnap = Loon._instance.documentStore.get(path);
    if (prevSnap == null) {
      throw Exception('Missing document $path');
    }

    return Loon._instance.writeDocument<T>(
      this,
      data,
      // As an optimization, broadcasting is skipped when updating a document if its
      // data is unchanged.
      broadcast: broadcast ?? prevSnap.data != data,
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

  /// Deletes the document. A narrowed document is deleted only while its data is [T].
  void delete() {
    final source = _source;
    if (source != null) {
      if (exists()) {
        source.delete();
      }
      return;
    }

    Loon._instance.deleteDocument<T>(this);
  }

  DocumentSnapshot<T>? get() {
    final source = _source;
    if (source == null) {
      return Loon._instance.getSnapshot(this);
    }

    final snap = source.get();
    if (snap == null) {
      return null;
    }
    final data = snap.data;
    return data is T ? DocumentSnapshot(doc: this, data: data) : null;
  }

  ObservableDocument<T> observe({
    bool multicast = false,
  }) {
    final source = _source;
    if (source != null) {
      return ObservableDocument<T>._narrowed(
        source,
        toJson: toJson,
        dependenciesBuilder: dependenciesBuilder,
        multicast: multicast,
      );
    }

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
    if (_source != null) {
      return get() != null;
    }

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

  /// Rebroadcasts the document as a [BroadcastEvents.touched] event. Useful when document or query
  /// observers should re-evaluate the document without rewriting or persisting its value.
  /// Rebroadcasting a document that does not exist does nothing.
  void rebroadcast() {
    if (!exists()) {
      return;
    }

    Loon._instance.broadcastManager
        .writeDocument(this, BroadcastEvents.touched);
  }

  /// Rebuild the document's dependencies with the [dependenciesBuilder].
  void rebuildDependencies() {
    final source = _source;
    if (source != null) {
      if (exists()) {
        source.rebuildDependencies();
      }
      return;
    }

    final snap = get();
    if (snap == null) {
      return;
    }

    Loon._instance.dependencyManager.updateDependencies(snap);
  }
}
