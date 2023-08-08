part of loon;

typedef ObservableChangeRecord<T> = (T prev, T next);

typedef Optional<T> = T?;

/// A mixin that provides an observable interface for the access and streaming of stored values.
mixin Observable<T> {
  late final StreamController<ObservableChangeRecord<T>> _controller;
  late final Stream<T> _valueStream;
  late T _value;
  late T _prevValue;
  late final bool multicast;

  init(
    T initialValue, {
    /// Whether the [Observable] can have more than one observable subscription. A single-subscription
    /// observable will release its resources automatically when its single subscription is canceled.
    /// A multicast observable must have its resources released manually by calling [dispose].
    /// The term *multicast* is used to refer to a a multi-subscription observable since it is common observable terminology and
    /// the term broadcast is used differently in the library compared to its usage in the underlying Dart [Stream] implementation.
    required bool multicast,
  }) {
    this.multicast = multicast;

    if (multicast) {
      _controller = StreamController<ObservableChangeRecord<T>>.broadcast();
    } else {
      _controller =
          StreamController<ObservableChangeRecord<T>>(onCancel: dispose);
    }

    _valueStream = _controller.stream.map((record) {
      final (_, next) = record;
      return next;
    });

    _prevValue = _value = initialValue;
    _controller.add((_prevValue, _value));
  }

  void dispose() {
    _controller.close();
  }

  bool get isClosed {
    return _controller.isClosed;
  }

  T add(T updatedValue) {
    _prevValue = _value;
    _value = updatedValue;
    _controller.add((_prevValue, _value));
    return _value;
  }

  T get();

  Stream<T> stream() {
    return _valueStream;
  }

  Stream<ObservableChangeRecord<T>> streamChanges() {
    return _controller.stream;
  }
}
