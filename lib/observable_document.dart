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
  /// 1. The document's collection has been removed.
  /// 2. The document has a broadcast event.
  @override
  void _onBroadcast() {
    // If the document's collection has been removed, then rebroadcast that the document was removed as well.
    if (Loon._instance.broadcastManager.store.get(parent) ==
            EventTypes.removed &&
        _value != null) {
      _addEvent(EventTypes.removed, null);
      return;
    }

    // 2. If there is a broadcast event for the document, emit it.
    final event = Loon._instance.broadcastManager.store.get(path);
    if (event != null) {
      _addEvent(event, get());
    }
  }

  _addEvent(EventTypes event, DocumentSnapshot<T>? snap) {
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

  @override
  ObservableDocument<T> observe({bool multicast = false}) {
    return this;
  }
}
