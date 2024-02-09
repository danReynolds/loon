part of loon;

class ObservableDocument<T> extends Document<T>
    with BroadcastObserver<DocumentSnapshot<T>?, DocumentChangeSnapshot<T>> {
  ObservableDocument({
    required super.collection,
    required super.id,
    super.fromJson,
    super.toJson,
    super.persistorSettings,
    super.dependenciesBuilder,
    required bool multicast,
  }) {
    init(super.get(), multicast: multicast);
  }

  /// Observing a document involves checking if it is included in the latest broadcast
  /// and if so, emitting an update to observers.
  @override
  void _onBroadcast() {
    final broadcastDoc = Loon._instance._getBroadcastDocument<T>(
      collection,
      id,
      fromJson: fromJson,
      toJson: toJson,
      persistorSettings: persistorSettings,
    );

    if (broadcastDoc == null) {
      return;
    }

    final snap = get();

    if (_changeController.hasListener) {
      _changeController.add(
        DocumentChangeSnapshot(
          doc: broadcastDoc,
          type: broadcastDoc.type,
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
