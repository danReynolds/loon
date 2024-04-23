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
    init(
      super.get(),
      multicast: multicast,
    );
  }

  /// On broadcast, the [ObservableDocument] examines the broadcast events that have occurred
  /// since the last broadcast and determines if the document needs to rebroadcast to its listeners.
  @override
  void _onBroadcast() {
    final event = Loon._instance.broadcastManager.store.get(path);
    if (event != null) {
      final snap = get();

      if (_changeController.hasListener) {
        _changeController.add(
          DocumentChangeSnapshot(
            doc: this,
            event: event,
            data: snap?.data,
            prevData: _value?.data,
          ),
        );
      }

      add(snap);
    }
  }

  @override
  ObservableDocument<T> observe({bool multicast = false}) {
    return this;
  }
}
