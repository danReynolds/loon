part of loon;

class ObservableDocument<T> extends Document<T>
    with
        Observable<DocumentSnapshot<T>?>,
        BroadcastObservable<DocumentSnapshot<T>?> {
  ObservableDocument({
    required super.collection,
    required super.id,
    super.fromJson,
    super.toJson,
    super.persistorSettings,
  }) {
    init(null);
  }

  /// Observing a document just involves checking if it is included in the latest broadcast
  /// and if so, emitting an update to observers.
  @override
  void _onBroadcast() {
    if (Loon._instance._isScheduledForBroadcast(this)) {
      add(get());
    }
  }
}
