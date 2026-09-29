part of './loon.dart';

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
    _init(_readSnapshot(), multicast: multicast);
  }

  /// Reads the document's snapshot from the store rather than the observer's cached value.
  DocumentSnapshot<T>? _readSnapshot() => super.get();

  /// Returns the change to report when a broadcast [event] leaves the document at [snap],
  /// or null to report nothing.
  BroadcastEvents? _changeEvent(
    BroadcastEvents event,
    DocumentSnapshot<T>? snap,
  ) =>
      event;

  /// On broadcast, the [ObservableDocument] examines the broadcast events that have occurred
  /// since the last broadcast and determines if the document needs to rebroadcast to its listeners.
  ///
  /// There are two scenarios where a document needs to be rebroadcast:
  /// 1. There is a broadcast event recorded for the document, including a [BroadcastEvents.touched]
  ///    event scheduled because a document it depends on was written or deleted.
  /// 2. There is a [BroadcastEvents.removed] event for any path above the document path.
  @override
  void _onBroadcast() {
    BroadcastEvents? event =
        Loon._instance.broadcastManager.eventStore.get(path);

    if (event == null &&
        Loon._instance.broadcastManager.eventStore
                .getNearestMatch(path, BroadcastEvents.removed) !=
            null) {
      event = BroadcastEvents.removed;
    }

    if (event != null) {
      final snap = get();
      final change = _changeEvent(event, snap);
      if (change == null) {
        return;
      }

      if (_changeController.hasListener) {
        _changeController.add(
          DocumentChangeSnapshot(
            doc: this,
            event: change,
            data: snap?.data,
            prevData: _controllerValue?.data,
          ),
        );
      }

      add(snap);
    }
  }

  @override
  get isDirty => _value == null && _readSnapshot() != null;

  @override
  ObservableDocument<T> observe({
    bool multicast = false,
  }) {
    return this;
  }

  @override
  get() {
    return _value ?? (_value = _readSnapshot());
  }
}
