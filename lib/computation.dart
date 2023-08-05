part of 'loon.dart';

/// A [Computation] is used to derive data from the composition of multiple computable inputs
/// consisting of [Document], [Query] and other [Computation] objects.
class Computation<T> extends Computable<T> {
  final T initialValue;
  final List<Computable> computables;
  final T Function(List inputs) compute;

  Computation({
    required this.initialValue,
    required this.computables,
    required this.compute,
  });

  static Computation<T> compute2<T, S1, S2>(
    T initialValue,
    Computable<S1> computable1,
    Computable<S2> computable2,
    T Function(S1 computable1, S2 computable2) compute,
  ) {
    return Computation<T>(
      initialValue: initialValue,
      computables: [computable1, computable2],
      compute: (inputs) => compute(inputs[0], inputs[1]),
    );
  }

  static Computation<T> compute3<T, S1, S2, S3>(
    T initialValue,
    Computable<S1> computable1,
    Computable<S2> computable2,
    Computable<S3> computable3,
    T Function(S1 computable1, S2 computable2, S3 computable3) compute,
  ) {
    return Computation<T>(
      initialValue: initialValue,
      computables: [computable1, computable2, computable3],
      compute: (inputs) => compute(inputs[0], inputs[1], inputs[2]),
    );
  }

  static Computation<T> compute4<T, S1, S2, S3, S4>(
    T initialValue,
    Computable<S1> computable1,
    Computable<S2> computable2,
    Computable<S3> computable3,
    Computable<S3> computable4,
    T Function(
      S1 computable1,
      S2 computable2,
      S3 computable3,
      S4 computable4,
    ) compute,
  ) {
    return Computation<T>(
      initialValue: initialValue,
      computables: [computable1, computable2, computable3, computable4],
      compute: (inputs) => compute(inputs[0], inputs[1], inputs[2], inputs[3]),
    );
  }

  @override
  get() {
    return compute(computables.map((computable) => computable.get()).toList());
  }

  @override
  asObservable() {
    return ObservableComputation<T>(
      initialValue: initialValue,
      computables: computables,
      compute: compute,
    );
  }

  @override
  stream() {
    return asObservable().stream();
  }

  @override
  streamChanges() {
    return asObservable().streamChanges();
  }
}
