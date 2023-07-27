part of loon;

class ObservableDocument<T> extends Document<T>
    with BroadcastObservable<DocumentSnapshot<T>?> {
  ObservableDocument({
    required super.path,
    required super.id,
    super.fromJson,
    super.toJson,
    super.persistorSettings,
  }) {
    observe(null);
  }

  @override

  /// Observing a document just involves checking if it is included in the latest broadcast
  /// and if so, rebroadcasting the update to observers.
  void _onBroadcast() {
    if (Loon._instance._isScheduledForBroadcast(this)) {
      rebroadcast(get());
    }
  }
}
