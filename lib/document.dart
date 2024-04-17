part of loon;

class Document<T> {
  final String id;
  final String parent;
  final FromJson<T>? fromJson;
  final ToJson<T>? toJson;
  final PersistorSettings? _persistorSettings;
  final DependenciesBuilder<T>? dependenciesBuilder;

  Document(
    this.parent,
    this.id, {
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
    // Documents are equivalent based on their ID and collection, however, observable documents
    // are not, since they have additional properties unique to their instance.
    if (other is Document && this is! ObservableDocument) {
      return other.path == path;
    }
    return false;
  }

  @override
  int get hashCode => Object.hashAll([parent, id]);

  String get path {
    if (parent == 'ROOT') {
      return id;
    }

    return "${parent}__$id";
  }

  static final root = Document('ROOT', 'ROOT');

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
      persistorSettings: persistorSettings,
      dependenciesBuilder: dependenciesBuilder,
    );
  }

  DocumentSnapshot<T> create(
    T data, {
    bool broadcast = true,
  }) {
    if (exists()) {
      throw Exception('Cannot create duplicate document');
    }

    return Loon._instance._writeDocument<T>(
      this,
      data,
      broadcast: broadcast,
      event: EventTypes.added,
    );
  }

  DocumentSnapshot<T> update(
    T data, {
    bool broadcast = true,
  }) {
    if (!exists()) {
      throw Exception('Missing document $path');
    }

    return Loon._instance._writeDocument<T>(
      this,
      data,
      // As an optimization, broadcasting is skipped when updating a document if the document
      // data is unchanged.
      broadcast: data != get()!.data,
      event: EventTypes.modified,
    );
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

  DocumentSnapshot<T> modify(
    ModifyFn<T> modifyFn, {
    bool broadcast = true,
  }) {
    return createOrUpdate(modifyFn(get()), broadcast: broadcast);
  }

  void delete({
    bool broadcast = true,
  }) {
    Loon._instance._deleteDocument<T>(this, broadcast: broadcast);
  }

  DocumentSnapshot<T>? get() {
    return Loon._instance._getDocument(this);
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

  Json? getJson() {
    final data = get()?.data;

    if (data is Json?) {
      return data;
    }

    return toJson!(data);
  }

  bool exists() {
    return get() != null;
  }

  bool isPersistenceEnabled() {
    return persistorSettings?.persistenceEnabled ?? false;
  }

  bool isPendingBroadcast() {
    return Loon._instance._broadcastStore.contains(path);
  }

  PersistorSettings? get persistorSettings {
    return _persistorSettings ?? Loon._instance.persistor?.settings;
  }
}
