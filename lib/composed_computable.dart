part of 'loon.dart';

class ComposedComputable<T> implements Computable<T> {
  final Computation<Computation<T>> computation;

  ComposedComputable(this.computation);

  @override
  get() {
    return computation.get().get();
  }

  @override
  ObservableComposedComputable<T> observe({
    bool multicast = false,
  }) {
    return ObservableComposedComputable(computation, multicast: multicast);
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
