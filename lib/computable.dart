part of 'loon.dart';

/// A computable is an object that exposes an interface for the accessing and streaming of stored value.
/// Computables include the [Document], [Query], [Computation] and [ComputableValue] implementations.
abstract interface class Computable<T> {
  T get();

  Stream<T> stream();

  Stream<ObservableChangeRecord<T>> streamChanges();
}
