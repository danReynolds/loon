part of loon;

class Document<T> {
  final String path;
  final String id;
  final FromJson<T>? fromJson;
  final ToJson<T>? toJson;
  final PersistorSettings? persistorSettings;

  Document({
    required this.path,
    required this.id,
    this.fromJson,
    this.toJson,
    this.persistorSettings,
  });

  void delete() {
    Loon._instance._deleteDocument<T>(this);
  }

  DocumentSnapshot<T> update(T data) {
    return Loon._instance._updateDocument<T>(this, data);
  }

  DocumentSnapshot<T> modify(ModifyFn<T> modifyFn) {
    return Loon._instance._modifyDocument(
      this,
      modifyFn,
    );
  }

  DocumentSnapshot<T> create(T data) {
    return Loon._instance._addDocument<T>(this, data);
  }

  DocumentSnapshot<T> createOrUpdate(T data) {
    if (exists()) {
      return update(data);
    }
    return create(data);
  }

  DocumentSnapshot<T>? get() {
    return Loon._instance._getSnapshot<T>(this);
  }

  ObservableDocument<T> asObservable() {
    return ObservableDocument<T>(
      id: id,
      path: path,
      fromJson: fromJson,
      toJson: toJson,
      persistorSettings: persistorSettings,
    );
  }

  Stream<DocumentSnapshot<T>?> stream() {
    return asObservable().stream();
  }

  Stream<BroadcastObservableChangeRecord<DocumentSnapshot<T>?>>
      streamChanges() {
    return asObservable().streamChanges();
  }

  Json? getJson() {
    final data = Loon._instance._getSnapshot<T>(this)?.data;

    if (data is Json?) {
      return data;
    }

    return toJson!(data);
  }

  bool exists() {
    return Loon._instance._hasDocument(this);
  }

  Collection<T> collection(String collection) {
    return Collection<T>(
      '$path/$id',
      fromJson: fromJson,
      toJson: toJson,
      persistorSettings: persistorSettings,
    );
  }
}

enum BroadcastEventTypes {
  /// The document has been modified.
  modified,

  /// The document has been added.
  added,

  /// The document has been removed.
  removed,

  /// The document has been manually touched for rebroadcast.
  touched,
}

class BroadcastDocument<T> extends Document<T> {
  final BroadcastEventTypes type;

  BroadcastDocument(
    Document<T> doc,
    this.type,
  ) : super(
          id: doc.id,
          path: doc.path,
          fromJson: doc.fromJson,
          toJson: doc.toJson,
          persistorSettings: doc.persistorSettings,
        );
}
