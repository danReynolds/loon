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

    _cacheDeps();
  }

  _cacheDeps() {
    final deps = dependencies();
    if (deps != _depCache) {
      _updateDeps(_depCache, deps);
      _depCache = deps;
    }
  }

  Set<Document>? _depCache = {};

  /// On broadcast, the [ObservableDocument] examines the broadcast events that have occurred
  /// since the last broadcast and determines if the document needs to rebroadcast to its listeners.
  ///
  /// There are three scenarios where a document needs to be rebroadcast:
  /// 1. There is a broadcast event recorded for the document.
  /// 2. There is a [BroadcastEvents.removed] event for any path above the document path.
  /// 3. The observable document itself has been touched for rebroadcast, such as in the case
  ///    of a dependency of the document having been removed.
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

    // 3.
    if (event == null &&
        Loon._instance.broadcastManager.eventStore.hasValue(_observerId)) {
      event = BroadcastEvents.touched;
    }

    if (event != null) {
      final snap = get();

      _cacheDeps();

      if (_changeController.hasListener) {
        _changeController.add(
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
    return this;
  }

  @override
  get() {
    return isDirty ? (_value = super.get()) : _value;
  }

  Map inspect() {
    return {
      "deps": _deps.inspect(),
    };
  }
}
