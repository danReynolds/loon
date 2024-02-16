part of loon;

class Document<T> {
  final String collection;
  final String id;
  final FromJson<T>? fromJson;
  final ToJson<T>? toJson;
  final PersistorSettings? _persistorSettings;
  final DependenciesBuilder<T>? dependenciesBuilder;

  Document({
    required this.collection,
    required this.id,
    this.fromJson,
    this.toJson,
    PersistorSettings? persistorSettings,
    this.dependenciesBuilder,
  }) : _persistorSettings = persistorSettings;

  @override
  bool operator ==(Object other) {
    if (identical(this, other)) {
      return true;
    }
    if (other is Document) {
      return id == other.id && collection == other.collection;
    }
    return false;
  }

  @override
  int get hashCode => Object.hashAll([id, collection]);

  String get key {
    return "$collection:$id";
  }

  Collection<S> subcollection<S>(
    String subcollection, {
    FromJson<S>? fromJson,
    ToJson<S>? toJson,
    PersistorSettings? persistorSettings,
    DependenciesBuilder<S>? dependenciesBuilder,
  }) {
    return Collection<S>(
      "${collection}_${id}_$subcollection",
      fromJson: fromJson,
      toJson: toJson,
      persistorSettings: persistorSettings,
      dependenciesBuilder: dependenciesBuilder,
    );
  }

  void delete({
    bool broadcast = true,
  }) {
    Loon._instance._deleteDocument<T>(this, broadcast: broadcast);
  }

  DocumentSnapshot<T> update(
    T data, {
    bool broadcast = true,
  }) {
    return Loon._instance._updateDocument<T>(this, data, broadcast: broadcast);
  }

  DocumentSnapshot<T> modify(
    ModifyFn<T> modifyFn, {
    bool broadcast = true,
  }) {
    return Loon._instance._modifyDocument(
      this,
      modifyFn,
      broadcast: broadcast,
    );
  }

  DocumentSnapshot<T> create(
    T data, {
    bool broadcast = true,
  }) {
    return Loon._instance._addDocument<T>(this, data, broadcast: broadcast);
  }

  DocumentSnapshot<T> createOrUpdate(
    T data, {
    bool broadcast = true,
  }) {
    if (exists()) {
      return update(data, broadcast: broadcast);
    }
    return create(data, broadcast: broadcast);
  }

  DocumentSnapshot<T>? get() {
    return Loon._instance._getSnapshot<T>(
      id: id,
      collection: collection,
      fromJson: fromJson,
      toJson: toJson,
      persistorSettings: persistorSettings,
    );
  }

  ObservableDocument<T> observe({
    bool multicast = false,
  }) {
    return ObservableDocument<T>(
      id: id,
      collection: collection,
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

  Json? getJson() {
    final data = get()?.data;

    if (data is Json?) {
      return data;
    }

    return toJson!(data);
  }

  bool exists() {
    return Loon._instance._hasDocument(this);
  }

  bool isPersistenceEnabled() {
    return persistorSettings?.persistenceEnabled ?? false;
  }

  bool isPendingBroadcast() {
    return Loon._instance._isDocumentPendingBroadcast(this);
  }

  PersistorSettings? get persistorSettings {
    return _persistorSettings ?? Loon._instance.persistor?.persistorSettings;
  }
}

enum DocumentBroadcastTypes {
  /// The document has been modified.
  modified,

  /// The document has been added.
  added,

  /// The document has been removed.
  removed,

  /// The document has been manually touched for rebroadcast.
  touched,

  /// The document has been hydrated from persisted storage.
  hydrated,
}
