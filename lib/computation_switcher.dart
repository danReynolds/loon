part of 'loon.dart';

/// A [ComputationSwitcher] is a higher-order [Computable] that wraps a [Computation] of computations.
/// This computable is necessary to support the [Computation.switchMap] operator, which switches to
/// emitting computed values from the most recent inner computation whenever a new outer computation is created.
class ComputationSwitcher<T> implements Computable<T> {
  final Computation<Computation<T>> computation;

  ComputationSwitcher(this.computation);

  @override
  get() {
    return computation.get().get();
  }

  @override
  ObservableComputationSwitcher<T> observe({
    bool multicast = false,
  }) {
    return ObservableComputationSwitcher(computation, multicast: multicast);
  }

  @override
  stream() {
    return observe().stream();
  }

  @override
  streamChanges() {
    return observe().streamChanges();
  }
}
