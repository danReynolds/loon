part of 'loon.dart';

/// A [Computation] is used to derive data from the composition of multiple [Computable] inputs
/// such as [Document], [Query] and [ComputedValue] implementations.
class Computation<T> with Computable<T> {
  final List<Computable> computables;
  final T Function(List inputs) compute;

  Computation({
    required this.computables,
    required this.compute,
  });

  static Computation<T> compute2<T, S1, S2>(
    Computable<S1> computable1,
    Computable<S2> computable2,
    T Function(S1 input1, S2 input2) compute,
  ) {
    return Computation<T>(
      computables: [computable1, computable2],
      compute: (inputs) => compute(inputs[0], inputs[1]),
    );
  }

  static Computation<T> compute3<T, S1, S2, S3>(
    Computable<S1> computable1,
    Computable<S2> computable2,
    Computable<S3> computable3,
    T Function(S1 input1, S2 input2, S3 input3) compute,
  ) {
    return Computation<T>(
      computables: [computable1, computable2, computable3],
      compute: (inputs) => compute(inputs[0], inputs[1], inputs[2]),
    );
  }

  static Computation<T> compute4<T, S1, S2, S3, S4>(
    Computable<S1> computable1,
    Computable<S2> computable2,
    Computable<S3> computable3,
    Computable<S3> computable4,
    T Function(
      S1 input1,
      S2 input2,
      S3 input3,
      S4 input4,
    ) compute,
  ) {
    return Computation<T>(
      computables: [computable1, computable2, computable3, computable4],
      compute: (inputs) => compute(inputs[0], inputs[1], inputs[2], inputs[3]),
    );
  }

  @override
  get() {
    return compute(computables.map((computable) => computable.get()).toList());
  }

  @override
  ObservableComputation<T> observe({
    bool multicast = false,
  }) {
    return ObservableComputation<T>(
      computables: computables,
      compute: compute,
      multicast: multicast,
    );
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
