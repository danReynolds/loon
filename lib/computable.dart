part of 'loon.dart';

/// A computable is an object that exposes an interface for accessing and streaming of stored value. A [Document], [Query] and [Computation]
/// are all examples of computables.
abstract interface class Computable<T> {
  T get();

  Stream<T> stream();

  Stream<ObservableChangeRecord<T>> streamChanges();

  Observable<T> asObservable();
}
