part of loon;

/// A mixin that provides an observable interface for the access and streaming of data broadcasted from the store.
mixin BroadcastObserver<T, S> {
  late final StreamController<T> _controller;
  late final StreamController<S> _changeController;
  late T _value;
  late final bool multicast;

  String get path;

  final _deps = PathRefStore();

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

    _value = initialValue;
    _controller.add(_value);

    Loon._instance.broadcastManager.addObserver(this);
  }

  void dispose() {
    _controller.close();
    _changeController.close();
    Loon._instance.broadcastManager.removeObserver(this);
  }

  T add(T updatedValue) {
    _value = updatedValue;
    _controller.add(_value);
    return _value;
  }

  bool exists();

  /// [get] is left unimplemented since it has variable logic based on the type of observer like an [ObservableDocument]
  /// and [ObservableQuery].
  T get();

  Stream<T> stream() {
    return _controller.stream;
  }

  Stream<S> streamChanges() {
    return _changeController.stream;
  }

  void _onBroadcast();

  bool isPendingBroadcast();
}
