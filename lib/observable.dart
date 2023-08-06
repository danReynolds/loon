part of loon;

typedef ObservableChangeRecord<T> = (T prev, T next);

/// A mixin that provides an observable interface for the access and streaming of stored value.
mixin Observable<T> {
  late final StreamController<ObservableChangeRecord<T>> _controller;
  late final Stream<T> _valueStream;
  late T value;
  late T prevValue;

  init([T? initialValue]) {
    _controller =
        StreamController<ObservableChangeRecord<T>>(onCancel: dispose);
    _valueStream = _controller.stream.asBroadcastStream().map((record) {
      final (_, next) = record;
      return next;
    });

    if (initialValue != null) {
      prevValue = value = initialValue;
    }

    add(get());
  }

  void dispose() {
    _controller.close();
  }

  void add(T updatedValue) {
    prevValue = value;
    value = updatedValue;
    _controller.add((prevValue, value));
  }

  T get();

  Stream<T> stream() {
    return _valueStream;
  }

  Stream<ObservableChangeRecord<T>> streamChanges() {
    return _controller.stream;
  }
}
