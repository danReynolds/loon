part of loon;

class Document<T> implements StoreReference {
  final String id;
  final String parent;
  final FromJson<T>? fromJson;
  final ToJson<T>? toJson;
  final PersistorSettings<T>? persistorSettings;
  final DependenciesBuilder<T>? dependenciesBuilder;

  Document(
    this.parent,
    this.id, {
    this.fromJson,
    this.toJson,
    this.persistorSettings,
    this.dependenciesBuilder,
  });

  static Document<T> _fromPath<T>(
    StoreReference ref,
    List<String> segments,
    int index,
  ) {
    if (index == segments.length) {
      if (ref is Document<T>) {
        return ref;
      }
    } else {
      final segment = segments[index];
      if (ref is Document) {
        return Document._fromPath(
          ref.subcollection<T>(segment),
          segments,
          index + 1,
        );
      } else if (ref is Collection) {
        return Document._fromPath(ref.doc(segment), segments, index + 1);
      }
    }

    throw 'Invalid path';
  }

  static Document<T> fromPath<T>(String path) {
    return Document._fromPath<T>(Document('', ''), path.split('__'), 0);
  }

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
    PersistorSettings<S>? persistorSettings,
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

    return Loon._instance.writeDocument<T>(
      this,
      data,
      broadcast: broadcast,
      event: BroadcastEvents.added,
    );
  }

  DocumentSnapshot<T> update(
    T data, {
    bool broadcast = true,
  }) {
    if (!exists()) {
      throw Exception('Missing document $path');
    }

    return Loon._instance.writeDocument<T>(
      this,
      data,
      // As an optimization, broadcasting is skipped when updating a document if the document
      // data is unchanged.
      broadcast: data != get()!.data,
      event: BroadcastEvents.modified,
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

  Set<Document>? dependencies() {
    return Loon._instance.dependenciesStore.get(path);
  }

  Set<Document>? dependents() {
    return Loon._instance.dependentsStore[this];
  }

  bool isPersistenceEnabled() {
    return persistorSettings?.enabled ??
        Loon._instance._isGlobalPersistenceEnabled;
  }

  bool isPendingBroadcast() {
    return Loon._instance.broadcastManager.store.hasValue(path);
  }
}
