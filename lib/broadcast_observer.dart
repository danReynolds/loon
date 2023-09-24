part of loon;

/// Extends an [Observable] by registering it to receive document broadcasts.
mixin BroadcastObserver<T, S> on Observable<T> {
  late final StreamController<S> _metaChangesController;

  @override
  void init(
    T initialValue, {
    required bool multicast,
  }) {
    if (multicast) {
      _metaChangesController = StreamController<S>.broadcast();
    } else {
      _metaChangesController = StreamController<S>();
    }

    super.init(initialValue, multicast: multicast);
    Loon._instance._addBroadcastObserver(this);
  }

  @override
  void dispose() {
    super.dispose();
    _metaChangesController.close();
    Loon._instance._removeBroadcastObserver(this);
  }

  void _onBroadcast();

  /// Streams meta changes to the observable.
  Stream<S> streamMetaChanges() {
    return _metaChangesController.stream;
  }
}
