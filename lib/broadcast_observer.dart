part of loon;

const uuid = Uuid();

/// A mixin that provides an observable interface for the access and streaming of data broadcasted from the store.
mixin BroadcastObserver<T, S> {
  late final StreamController<T> _controller;
  late final StreamController<S> _changeController;
  late final bool multicast;

  /// The latest value emitted on the observer's stream controller. This value can be different
  /// from the *current* value of the observer, which may not have been broadcast on its stream yet
  /// and is cached in the [BroadcastManager].
  late T _controllerValue;

  String get path;

  final _deps = PathRefStore();

  /// The path of the broadcast observer in the observer value store.
  late String _storePath;

  void init(
    T initialValue, {
    /// Whether the [Observable] can have more than one observable subscription. A single-subscription
    /// observable will allow one listener and release its resources automatically when its listener cancels its subscription.
    /// A multicast observable must have its resources released manually by calling [dispose].
    /// The term *multicast* is used to refer to a a multi-subscription observable since it is common observable terminology and
    /// the term broadcast is to mean something different in the library compared to its usage in the underlying Dart [Stream] implementation.
    required bool multicast,
  }) {
    this.multicast = multicast;

    if (multicast) {
      _controller = StreamController<T>.broadcast();
      _changeController = StreamController<S>.broadcast();
    } else {
      _controller = StreamController<T>(onCancel: dispose);
      _changeController = StreamController<S>(onCancel: dispose);
    }

    _controllerValue = initialValue;
    _controller.add(initialValue);

    _storePath = "${path}__${uuid.v4()}";

    Loon._instance.broadcastManager.addObserver(this, initialValue);
  }

  void dispose() {
    _controller.close();
    _changeController.close();
    Loon._instance.broadcastManager.removeObserver(this);
  }

  T add(T updatedValue) {
    Loon._instance.broadcastManager.observerValueStore
        .write(this._storePath, updatedValue);
    _controller.add(updatedValue);
    return _controllerValue = updatedValue;
  }

  Stream<T> stream() {
    return _controller.stream;
  }

  Stream<S> streamChanges() {
    return _changeController.stream;
  }

  T? get value {
    return Loon._instance.broadcastManager.observerValueStore.get(this);
  }

  set value(T? value) {
    Loon._instance.broadcastManager.observerValueStore.write(this, value);
  }

  /// Returns whether the observer has a cached value in the [ObserverValueStore].
  bool get hasValue {
    return Loon._instance.broadcastManager.observerValueStore.hasValue(this);
  }

  void _onBroadcast();
}
