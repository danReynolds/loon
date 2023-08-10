part of 'loon.dart';

class ObservableComposedComputable<T> extends ComposedComputable<T>
    with Observable<T>
    implements Computable<T> {
  late StreamSubscription<Computation<T>> outerStreamSubscription;
  StreamSubscription<T>? innerStreamSubscription;

  ObservableComposedComputable(
    super.computation, {
    required bool multicast,
  }) {
    final observableComputation = computation.observe();
    final initialObservableInnerComputation =
        observableComputation.get().observe();

    outerStreamSubscription =
        // Skip the first outer computation event as it is precomputed above as the
        // inintial inner computation.
        observableComputation.stream().skip(1).listen((innerComputation) {
      innerStreamSubscription?.cancel();
      innerStreamSubscription =
          innerComputation.stream().listen(add, onDone: () {
        innerStreamSubscription!.cancel();
      });
    }, onDone: () {
      dispose();
    });

    innerStreamSubscription = initialObservableInnerComputation
        .stream()
        // Skip the first inner computation event as it is emitted on the composed computable stream
        // by the call to [init].
        .skip(1)
        .listen(add, onDone: () {
      innerStreamSubscription!.cancel();
    });

    init(
      initialObservableInnerComputation.get(),
      multicast: multicast,
    );
  }

  @override
  dispose() {
    super.dispose();
    outerStreamSubscription.cancel();
    innerStreamSubscription?.cancel();
  }

  @override
  ObservableComposedComputable<T> observe({bool multicast = false}) {
    return this;
  }

  @override
  get() {
    return _value;
  }
}
