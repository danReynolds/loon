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

  void delete() {
    Loon.instance._deleteDocument<T>(this);
  }

  DocumentSnapshot<T> update(T data) {
    return Loon.instance._updateDocument<T>(this, data);
  }

  DocumentSnapshot<T> modify(ModifyFn<T> modifyFn) {
    return Loon.instance._modifyDocument(
      this,
      modifyFn,
    );
  }

  DocumentSnapshot<T> create(T data) {
    return Loon.instance._addDocument<T>(this, data);
  }

  DocumentSnapshot<T>? get() {
    final data = Loon.instance._getDocumentData<T>(this);

    if (data != null) {
      return DocumentSnapshot<T>(doc: this, data: data);
    }
    return null;
  }

  ObservableDocument<T> asObservable() {
    return ObservableDocument<T>(
      id: id,
      collection: collection,
      fromJson: fromJson,
      toJson: toJson,
      persistorSettings: persistorSettings,
    );
  }

  Stream<DocumentSnapshot<T>?> stream() {
    return asObservable().stream();
  }

  Json? getJson() {
    return Loon.instance._getSerializedDocumentData(this);
  }

  bool exists() {
    return Loon.instance._hasDocument(this);
  }
}

enum BroadcastEventTypes {
  modified,
  added,
  removed,
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
