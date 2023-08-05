part of 'loon.dart';

class ObservableComputation<T> extends Computation<T> with Observable<T> {
  final List<StreamSubscription> _subscriptions = [];
  late List computableValues;

  bool _hasScheduledRecomputation = false;

  ObservableComputation({
    required super.initialValue,
    required super.computables,
    required super.compute,
  }) {
    init(initialValue);
  }

  void _scheduleRecomputation() {
    if (!_hasScheduledRecomputation) {
      _hasScheduledRecomputation = true;

      scheduleMicrotask(() {
        _hasScheduledRecomputation = false;
        add(compute(computableValues));
      });
    }
  }

  @override
  init(initialValue) {
    super.init(initialValue);

    computableValues = List.filled(computables.length, null);

    for (int i = 0; i < computables.length; i++) {
      _subscriptions.add(
        /// Skip the current value emitted by each [Computable] since the first computation value
        /// is pre-computed as one initial update rather than n initial updates where n is the number of computables.
        computables[i].stream().skip(1).listen(
          (inputValue) {
            computableValues[i] = inputValue;
            _scheduleRecomputation();
          },
        ),
      );
    }
  }

  @override
  dispose() {
    super.dispose();
    for (final subscription in _subscriptions) {
      subscription.cancel();
    }
  }
}
