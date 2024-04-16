part of loon;

class Document<T> extends StoreNode {
  final FromJson<T>? fromJson;
  final ToJson<T>? toJson;
  final PersistorSettings? _persistorSettings;
  final DependenciesBuilder<T>? dependenciesBuilder;

  DocumentSnapshot<T>? _snap;

  Document(
    String id, {
    super.children,
    super.parent,
    this.fromJson,
    this.toJson,
    PersistorSettings? persistorSettings,
    this.dependenciesBuilder,
  })  : _persistorSettings = persistorSettings,
        super(id);

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
  int get hashCode => Object.hashAll([parent?.path, id]);

  String get id {
    return name;
  }

  Collection<S> subcollection<S>(
    String name, {
    FromJson<S>? fromJson,
    ToJson<S>? toJson,
    PersistorSettings? persistorSettings,
    DependenciesBuilder<S>? dependenciesBuilder,
  }) {
    final node = children?[name];
    if (node is Collection<S>) {
      return node;
    }

    return Collection<S>(
      name,
      parent: this,
      children: node?.children,
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

    final snap = _snap = DocumentSnapshot<T>(
      doc: this,
      data: data,
    );

    parent?._addChild(this);

    Loon._instance._onWrite<T>(
      this,
      broadcast: broadcast,
      event: EventTypes.added,
    );

    return snap;
  }

  DocumentSnapshot<T> update(
    T data, {
    bool broadcast = true,
  }) {
    if (!exists()) {
      throw Exception('Missing document $path');
    }

    final prevSnap = _snap;
    final snap = _snap = DocumentSnapshot<T>(
      doc: this,
      data: data,
    );

    Loon._instance._onWrite<T>(
      this,
      // As an optimization, broadcasting is skipped when updating a document if the document
      // data is unchanged.
      broadcast: snap.data != prevSnap!.data,
      event: EventTypes.modified,
    );

    return snap;
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
    if (!exists()) {
      return;
    }

    parent?._removeChild(this);

    Loon._instance._onDelete<T>(this, broadcast: broadcast);
  }

  DocumentSnapshot<T>? get() {
    return _snap;
  }

  ObservableDocument<T> observe({
    bool multicast = false,
  }) {
    return ObservableDocument<T>(
      id,
      parent: parent,
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
    return Loon._instance._isDocumentPendingBroadcast(this);
  }

  PersistorSettings? get persistorSettings {
    return _persistorSettings ?? Loon._instance.persistor?.settings;
  }
}
