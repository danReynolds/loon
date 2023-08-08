part of 'loon.dart';

class ObservableComputation<T> extends Computation<T> with Observable<T> {
  final List<StreamSubscription> _subscriptions = [];
  late List _computableValues;

  bool _hasPendingRecomputation = false;

  ObservableComputation({
    required super.computables,
    required super.compute,
    required bool multicast,
  }) {
    _computableValues = List.filled(computables.length, null);

    for (int i = 0; i < computables.length; i++) {
      _subscriptions.add(
        /// Skip the current value emitted by each [Computable] since the first computation value
        /// is pre-computed as one initial update rather than n initial updates where n is the number of computables.
        computables[i].stream().skip(1).listen(
          (inputValue) {
            _computableValues[i] = inputValue;
            _scheduleRecomputation();
          },
        ),
      );
    }
    init(super.get(), multicast: multicast);
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
  get() {
    if (_hasPendingRecomputation) {
      return _recompute();
    }
    return _value;
  }
}
