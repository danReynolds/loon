part of './loon.dart';

class ObservableDocument<T> extends Document<T>
    with BroadcastObserver<DocumentSnapshot<T>?, DocumentChangeSnapshot<T>> {
  ObservableDocument(
    String parent,
    String id, {
    FromJson<T>? fromJson,
    ToJson<T>? toJson,
    PersistorSettings? persistorSettings,
    DependenciesBuilder<T>? dependenciesBuilder,
    required bool multicast,
  }) : super(
          parent,
          id,
          fromJson: fromJson,
          toJson: toJson,
          persistorSettings: persistorSettings,
          dependenciesBuilder: dependenciesBuilder,
        ) {
    _init(super.get(), multicast: multicast);
  }

  /// On broadcast, the [ObservableDocument] examines the broadcast events that have occurred
  /// since the last broadcast and determines if the document needs to rebroadcast to its listeners.
  ///
  /// There are two scenarios where a document needs to be rebroadcast:
  /// 1. There is a broadcast event recorded for the document, including a [BroadcastEvents.touched]
  ///    event scheduled because a document it depends on was written or deleted.
  /// 2. There is a [BroadcastEvents.removed] event for any path above the document path.
  @override
  void _onBroadcast() {
    BroadcastEvents? event;

    // 1.
    event = Loon._instance.broadcastManager.eventStore.get(path);

    // 2.
    final isRemoved = Loon._instance.broadcastManager.eventStore
            .getNearestMatch(path, BroadcastEvents.removed) !=
        null;

    if (event == null && isRemoved) {
      event = BroadcastEvents.removed;
    }

    if (event != null) {
      final snap = get();

      final changeController = _changeController;
      if (changeController != null && changeController.hasListener) {
        changeController.add(
          DocumentChangeSnapshot(
            doc: this,
            event: event,
            data: snap?.data,
            prevData: _controllerValue?.data,
          ),
        );
      }

      add(snap);
    }
  }

  @override
  get isDirty => _value == null && super.get() != null;

  @override
  ObservableDocument<T> observe({
    bool multicast = false,
  }) {
    // A disposed observable no longer observes anything, so a fresh one is returned instead.
    if (_disposed) {
      return ObservableDocument<T>(
        parent,
        id,
        fromJson: fromJson,
        toJson: toJson,
        persistorSettings: persistorSettings,
        dependenciesBuilder: dependenciesBuilder,
        multicast: multicast,
      );
    }
    return this;
  }

  @override
  get() {
    return isDirty ? (_value = super.get()) : _value;
  }
}
