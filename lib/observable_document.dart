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

  /// Observing a document involves checking if it is included in the latest broadcast
  /// and if so, emitting an update to observers.
  @override
  void _onBroadcast() {
    final event = Loon._instance._broadcastStore.get(path);

    if (event == null) {
      return;
    }

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

  @override
  _onClear() {
    if (_changeController.hasListener) {
      _changeController.add(
        DocumentChangeSnapshot(
          doc: this,
          event: EventTypes.removed,
          data: null,
          prevData: _value?.data,
        ),
      );
    }

    add(null);
  }

  @override
  ObservableDocument<T> observe({bool multicast = false}) {
    return this;
  }
}
