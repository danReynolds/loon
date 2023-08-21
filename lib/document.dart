part of loon;

class Document<T> {
  final String collection;
  final String id;
  final FromJson<T>? fromJson;
  final ToJson<T>? toJson;
  final PersistorSettings? persistorSettings;

  Document({
    required this.collection,
    required this.id,
    this.fromJson,
    this.toJson,
    this.persistorSettings,
  });

  Collection<S> subcollection<S>(
    String subcollection, {
    FromJson<S>? fromJson,
    ToJson<S>? toJson,
    PersistorSettings<S>? persistorSettings,
  }) {
    return Collection<S>(
      "${collection}_${id}_$subcollection",
      fromJson: fromJson,
      toJson: toJson,
      persistorSettings: persistorSettings,
    );
  }

  void delete() {
    Loon._instance._deleteDocument<T>(this);
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
    return Loon._instance._getSnapshot<T>(this);
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
    );
  }

  Stream<DocumentSnapshot<T>?> stream() {
    return observe().stream();
  }

  Stream<(DocumentSnapshot<T>?, DocumentSnapshot<T>?)> streamChanges() {
    return observe().streamChanges();
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
          collection: doc.collection,
          fromJson: doc.fromJson,
          toJson: doc.toJson,
          persistorSettings: doc.persistorSettings,
        );
}
