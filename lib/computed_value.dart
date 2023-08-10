part of 'loon.dart';

/// A simple [Computable] used to wrap an arbitrary value when needing to return work with a [Computable]
/// such as when return a value from [Computable.switchMap] or as an input to a [Computation].
class ComputedValue<T> with Computable<T> {
  final T value;

  ComputedValue(this.value);

  @override
  get() {
    return value;
  }

  @override
  stream() {
    return Stream.value(value);
  }

  @override
  observe({
    bool multicast = false,
  }) {
    return ObservableComputedValue(value, multicast: multicast);
  }

  @override
  Stream<ObservableChangeRecord<T>> streamChanges() {
    return Stream.value((value, value));
  }
}

class ObservableComputedValue<T> with Observable<T>, Computable<T> {
  ObservableComputedValue(
    T value, {
    required bool multicast,
  }) {
    init(
      value,
      multicast: multicast,
    );
  }

  @override
  T get() {
    return _value;
  }

  @override
  Observable<T> observe({bool multicast = false}) {
    return this;
  }
}
