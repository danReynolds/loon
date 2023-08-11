part of 'loon.dart';

/// A computable is an object that exposes an interface for the accessing and streaming of stored value.
/// Computables include the [Document], [Query], [Computation] and [ComputedValue] implementations.
mixin Computable<T> {
  /// Returns the current value of the [Computable] object.
  T get();

  /// Returns a [Stream] of values, emitting the current value of the [Computable] and updating whenever any of the computable's
  /// input data changes.
  Stream<T> stream();

  /// Returns an [Observable] computable that emits updates to its value through the [Observable.stream] API. Access to the [Observable] object is necessary
  /// for [Computable] objects that need to be multicast, as the default [Computable.stream] API only supports one listener.
  Observable<T> observe({
    bool multicast = false,
  });

  /// Emits a [Stream] of [ObservableChangeRecord] updates with the previous and current value of the computable value.
  Stream<ObservableChangeRecord<T>> streamChanges();

  /// Maps the current [Computable] to a new [Computable] with the applied transform.
  Computable<S> map<S>(S Function(T input) transform) {
    return Computation<S>(
      computables: [this],
      compute: (input) => transform(input[0]),
    );
  }

  /// Maps the current [Computable] to another [Computable] that switches to emitting values from the most recent
  /// inner computable whenever a new outer computable is created.
  Computable<S> switchMap<S>(Computable<S> Function(T input) transform) {
    return Computation<S>(
      computables: [ComputableSwitcher<S>(map(transform))],
      compute: (inputs) => inputs[0],
    );
  }

  /// Returns a [Computable] from a static value. Useful when needing to return a static value from a [Computable.switchMap] or
  /// when providing one as an input to a [Computation].
  static Computable<T> fromValue<T>(
    T value, {
    bool multicast = false,
  }) {
    return ComputedValue(
      value,
      multicast: multicast,
    );
  }

  /// Returns a [Computable] that emits data from the given [Stream]. Useful when needing to return a [Stream] from a [Computable.switchMap]
  /// or when providing one as an input to a [Computation].
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

  /// Returns a [Computable] that emits the resolved value of the given [Future]. Useful when needing to return a [Future] from a [Computable.switchMap]
  /// or when providing one as an input to a [Computation].
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
