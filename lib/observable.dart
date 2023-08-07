part of loon;

typedef ObservableChangeRecord<T> = (T prev, T next);

typedef Optional<T> = T?;

/// A mixin that provides an observable interface for the access and streaming of stored value.
mixin Observable<T> {
  late final StreamController<ObservableChangeRecord<T>> _controller;
  late final Stream<T> _valueStream;
  late T _value;
  late T _prevValue;

  init(T initialValue) {
    _controller =
        StreamController<ObservableChangeRecord<T>>(onCancel: dispose);
    _valueStream = _controller.stream.asBroadcastStream().map((record) {
      final (_, next) = record;
      return next;
    });

    _prevValue = _value = initialValue;
    add(get());
  }

  void dispose() {
    _controller.close();
  }

  void add(T updatedValue) {
    _prevValue = _value;
    _value = updatedValue;
    _controller.add((_prevValue, _value));
  }

  T get();

  Stream<T> stream() {
    return _valueStream;
  }

  Stream<ObservableChangeRecord<T>> streamChanges() {
    return _controller.stream;
  }
}
