part of 'loon.dart';

/// A computable is an object that exposes an interface for the accessing and streaming of stored value.
/// Computables include the [Document], [Query], [Computation] and [ComputedValue] implementations.
mixin Computable<T> {
  T get();

  Stream<T> stream();

  Observable<T> observe({
    bool multicast = false,
  });

  Stream<ObservableChangeRecord<T>> streamChanges();

  Computable<S> map<S>(S Function(T input) transform) {
    return Computation<S>(
      computables: [this],
      compute: (input) => transform(input[0]),
    );
  }

  Computable<S> switchMap<S>(Computable<S> Function(T input) transform) {
    return Computation<S>(
      computables: [ComputableSwitcher<S>(map(transform))],
      compute: (inputs) => inputs[0],
    );
  }

  static Computable<T> fromValue<T>(
    T value, {
    bool multicast = false,
  }) {
    return ComputedValue(
      value,
      multicast: multicast,
    );
  }

  static Computable<T> fromStream<T>(
    Stream<T> stream, {
    T? initialValue,
    bool multicast = false,
  }) {
    return ComputedStream<T>(
      stream,
      initialValue: initialValue,
      multicast: multicast,
    );
  }

  static Computable<T> fromFuture<T>(
    Future<T> future, {
    T? initialValue,
    bool multicast = false,
  }) {
    return ComputedFuture<T>(
      future,
      initialValue: initialValue,
      multicast: multicast,
    );
  }
}
