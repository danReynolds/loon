part of loon;

class ObservableDocument<T> extends Document<T>
    with
        Observable<DocumentSnapshot<T>?>,
        BroadcastObserver<DocumentSnapshot<T>?, BroadcastDocument<T>> {
  ObservableDocument({
    required super.collection,
    required super.id,
    super.fromJson,
    super.toJson,
    super.persistorSettings,
    required bool multicast,
  }) {
    init(super.get(), multicast: multicast);
  }

  /// Observing a document just involves checking if it is included in the latest broadcast
  /// and if so, emitting an update to observers.
  @override
  void _onBroadcast() {
    final broadcastDoc = Loon._instance._getBroadcastDocument<T>(
      collection,
      id,
      fromJson: fromJson,
      toJson: toJson,
      persistorSettings: persistorSettings,
    );

    if (broadcastDoc != null) {
      _metaChangesController.add(broadcastDoc);
      add(super.get());
    }
  }

  @override
  ObservableDocument<T> observe({bool multicast = false}) {
    return this;
  }

  @override
  get() {
    if (Loon._instance._isDocumentPendingBroadcast(this)) {
      return super.get();
    }
    return _value;
  }
}
