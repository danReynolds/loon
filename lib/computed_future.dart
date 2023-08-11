part of 'loon.dart';

class ComputedFuture<T> with Computable<T>, Observable<T> {
  final Future<T> future;

  ComputedFuture(
    this.future, {
    T? initialValue,
    bool multicast = false,
  }) {
    assert(
      initialValue != null || T == Optional<T>,
      'ComputedFuture must specify a nullable type or an initial value.',
    );

    future.then(add);

    init(initialValue as T, multicast: multicast);
  }

  @override
  get() {
    return _value;
  }

  @override
  observe({
    bool multicast = false,
  }) {
    return this;
  }
}
