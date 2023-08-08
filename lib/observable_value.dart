part of 'loon.dart';

class ObservableValue<T> with Observable<T> implements Computable<T> {
  ObservableValue(
    T value, {
    bool multicast = false,
  }) {
    init(value, multicast: multicast);
  }

  @override
  get() {
    return _value;
  }
}
