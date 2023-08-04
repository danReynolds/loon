part of 'loon.dart';

class Computation<T> extends Computable<T> {
  final T initialValue;
  final List<Computable> computables;
  final T Function(List inputs) compute;

  Computation({
    required this.initialValue,
    required this.computables,
    required this.compute,
  });

  static Computable<T> compute2<T, S1, S2>(
    Computable<S1> computable1,
    Computable<S2> computable2,
    T initialValue,
    T Function(S1 computable1, S2 computable2) compute,
  ) {
    return Computation<T>(
      computables: [computable1, computable2],
      initialValue: initialValue,
      compute: (inputs) => compute(inputs[0], inputs[1]),
    );
  }

  ObservableComputation<T> asObservable() {
    return ObservableComputation<T>(
      initialValue: initialValue,
      computables: computables,
      compute: compute,
    );
  }

  @override
  T get() {
    return compute(
      computables.map((computable) => computable.get()).toList(),
    );
  }

  @override
  Stream<T> stream() {
    return asObservable().stream();
  }
}
