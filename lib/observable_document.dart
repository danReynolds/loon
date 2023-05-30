part of loon;

class ObservableDocument<T> extends Document<T>
    with BroadcastObservable<DocumentSnapshot<T>?> {
  ObservableDocument({
    required super.collection,
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
    final broadcastDocuments =
        Loon._instance._getBroadcastDocuments(collection);
    final shouldBroadcast = broadcastDocuments
        .where((element) => element.id == id)
        .toList()
        .isNotEmpty;

    if (!shouldBroadcast) {
      return;
    }

    rebroadcast(get());
  }
}
