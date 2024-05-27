part of loon;

class ObservableDocument<T> extends Document<T>
    with BroadcastObserver<DocumentSnapshot<T>?, DocumentChangeSnapshot<T>> {
  ObservableDocument(
    super.parent,
    super.id, {
    super.fromJson,
    super.toJson,
    super.persistorSettings,
    super.dependenciesBuilder,
    required bool multicast,
  }) {
    init(super.get(), multicast: multicast);
  }

  /// On broadcast, the [ObservableDocument] examines the broadcast events that have occurred
  /// since the last broadcast and determines if the document needs to rebroadcast to its listeners.
  ///
  /// There are two scenarios where a document needs to be rebroadcast:
  /// 1. There is a broadcast event recorded for the document itself.
  /// 2. There is a [BroadcastEvents.removed] event for any path above the document path.
  @override
  void _onBroadcast() {
    // 1.
    final docEvent = Loon._instance.broadcastManager.store.get(path);

    // 2.
    final isRemoved = Loon._instance.broadcastManager.store
            .findValue(path, BroadcastEvents.removed) !=
        null;

    if (docEvent != null || isRemoved) {
      final snap = get();

      if (_changeController.hasListener) {
        _changeController.add(
          DocumentChangeSnapshot(
            doc: this,
            event: docEvent ?? BroadcastEvents.removed,
            data: snap?.data,
            prevData: _value?.data,
          ),
        );
      }

      add(snap);
    }
  }

  @override
  ObservableDocument<T> observe({
    bool multicast = false,
  }) {
    return this;
  }
}
