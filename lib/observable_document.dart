part of loon;

class ObservableDocument<T> extends Document<T>
    with BroadcastObserver<DocumentSnapshot<T>?, DocumentChangeSnapshot<T>> {
  DocumentSnapshot<T>? _prevValue;

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

  /// There are two broadcast scenarios handled by an observable document.
  /// 1. The broadcast does not include an event for the document, but the document's value
  ///    no longer exists in the store (and previous did). In this scenario, the observable emits
  ///    a [EventTypes.removed] event to listeners.
  /// 2. The broadcast includes an event for the document, in which case it emits the new event to listeners.
  @override
  void _onBroadcast() {
    // 1. If the document no longer exists at the time of this broadcast and it's last value is non-null,
    // then emit an [EventTypes.removed] event for listeners.
    if (!exists() && _prevValue != null) {
      _addEvent(EventTypes.removed, null);
      return;
    }

    // 2. Otherwise, if there is a broadcast event for the document, emit it.
    final event = Loon._instance._broadcastManager.getBroadcast(this);
    if (event != null) {
      _addEvent(event, get());
    }
  }

  _addEvent(EventTypes event, DocumentSnapshot<T>? snap) {
    _prevValue = _value;

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
