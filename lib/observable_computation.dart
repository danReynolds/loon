part of 'loon.dart';

class ObservableComputation<T> extends Computation<T> with Observable<T> {
  final List<StreamSubscription> _subscriptions = [];
  late List _computableValues;
  int _completedSubscriptionCount = 0;

  bool _hasPendingRecomputation = false;

  ObservableComputation({
    required super.computables,
    required super.compute,
    required bool multicast,
  }) {
    _computableValues = List.filled(computables.length, null);

    for (int i = 0; i < computables.length; i++) {
      final observedComputable = computables[i].observe();

      _subscriptions.add(
        /// Skip the current value emitted by each [Computable] since the first computation value
        /// is pre-computed as one initial update by the call to [init].
        observedComputable.stream().skip(1).listen((inputValue) {
          _computableValues[i] = inputValue;
          _scheduleRecomputation();
        }, onDone: () {
          _completedSubscriptionCount++;
          if (_completedSubscriptionCount == _subscriptions.length) {
            dispose();
          }
        }),
      );
      _computableValues[i] = observedComputable.get();
    }

    init(compute(_computableValues), multicast: multicast);
  }

  void _scheduleRecomputation() {
    if (!_hasPendingRecomputation) {
      _hasPendingRecomputation = true;
      scheduleMicrotask(_recompute);
    }
  }

  T _recompute() {
    _hasPendingRecomputation = false;
    return add(compute(_computableValues));
  }

  @override
  dispose() {
    super.dispose();
    for (final subscription in _subscriptions) {
      subscription.cancel();
    }
  }

  @override
  ObservableComputation<T> observe({bool multicast = false}) {
    return this;
  }

  @override
  get() {
    if (_hasPendingRecomputation) {
      return _recompute();
    }
    return _value;
  }
}
