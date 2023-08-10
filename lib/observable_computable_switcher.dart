part of 'loon.dart';

/// An [ObservableComputableSwitcher] is a higher-order [Computable] that is necessary to support the
/// [Computable.switchMap] operator, which switches to emitting values from the most recent
/// inner computable whenever a new outer computable is created.
class ObservableComputableSwitcher<T> extends ComputableSwitcher<T>
    with Observable<T> {
  late StreamSubscription<Computable<T>> outerStreamSubscription;
  StreamSubscription<T>? innerStreamSubscription;

  ObservableComputableSwitcher(
    super.computable, {
    required bool multicast,
  }) {
    final observedComputable = computable.observe();
    final initialObservedInnerComputable = observedComputable.get().observe();

    outerStreamSubscription =
        // Skip the first outer computation event as it is precomputed above as the
        // inintial inner computation.
        observedComputable.stream().skip(1).listen((innerComputation) {
      innerStreamSubscription?.cancel();
      innerStreamSubscription =
          innerComputation.stream().listen(add, onDone: () {
        innerStreamSubscription!.cancel();
      });
    }, onDone: () {
      dispose();
    });

    innerStreamSubscription = initialObservedInnerComputable
        .stream()
        // Skip the first inner computation event as it is emitted on the composed computable stream
        // by the call to [init].
        .skip(1)
        .listen(add, onDone: () {
      innerStreamSubscription!.cancel();
    });

    init(
      initialObservedInnerComputable.get(),
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
  ObservableComputableSwitcher<T> observe({bool multicast = false}) {
    return this;
  }

  @override
  get() {
    return _value;
  }
}
