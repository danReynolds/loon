part of loon;

/// A mixin that provides an observable interface for the access and streaming of stored values.
mixin Observable<T> {
  late final StreamController<T> _controller;
  late T _value;
  late final bool multicast;

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
    } else {
      _controller = StreamController<T>(onCancel: dispose);
    }

    _value = initialValue;
    _controller.add(_value);
  }

  void dispose() {
    _controller.close();
  }

  bool get isClosed {
    return _controller.isClosed;
  }

  T add(T updatedValue) {
    if (_controller.isClosed) {
      return _value;
    }

    _value = updatedValue;
    _controller.add(_value);
    return _value;
  }

  /// [get] is left unimplemented since it has variable logic based on the type of [Observable] like an [ObservableDocument]
  /// and [ObservableQuery].
  T get();

  Stream<T> stream() {
    return _controller.stream;
  }
}
