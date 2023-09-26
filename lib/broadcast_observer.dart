part of loon;

/// Extends an [Observable] by registering it to receive document broadcasts.
mixin BroadcastObserver<T, S> on Observable<T> {
  late final StreamController<S> _changesController;

  @override
  void init(
    T initialValue, {
    required bool multicast,
  }) {
    if (multicast) {
      _changesController = StreamController<S>.broadcast();
    } else {
      _changesController = StreamController<S>();
    }

    super.init(initialValue, multicast: multicast);
    Loon._instance._addBroadcastObserver(this);
  }

  @override
  void dispose() {
    super.dispose();
    _changesController.close();
    Loon._instance._removeBroadcastObserver(this);
  }

  void _onBroadcast();

  bool get hasChangeListener {
    return _changesController.hasListener;
  }

  void broadcastChanges(S changes) {
    _changesController.add(changes);
  }

  Stream<S> streamChanges() {
    return _changesController.stream;
  }
}
