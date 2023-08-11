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
    final initialInnerObservedComputable = observedComputable.get().observe();

    outerStreamSubscription =
        // Skip the first emitted inner computation as it is precomputed above as the
        // initial inner computable.
        observedComputable.stream().skip(1).listen(
      (innerComputable) {
        innerStreamSubscription?.cancel();
        innerStreamSubscription =
            innerComputable.stream().listen(add, onDone: () {
          innerStreamSubscription!.cancel();
        });
      },
      onDone: dispose,
    );

    innerStreamSubscription = initialInnerObservedComputable
        .stream()
        // Skip the first emitted inner computation event as it is emitted on the computable stream
        // by the call to [init].
        .skip(1)
        .listen(add, onDone: () {
      innerStreamSubscription!.cancel();
    });

    init(
      initialInnerObservedComputable.get(),
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
