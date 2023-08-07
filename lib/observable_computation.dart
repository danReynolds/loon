part of 'loon.dart';

class ObservableComputation<T> extends Computation<T> with Observable<T> {
  final List<StreamSubscription> _subscriptions = [];
  late List _computableValues;

  bool _hasScheduledRecomputation = false;

  ObservableComputation({
    required super.computables,
    required super.compute,
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
    init(super.get());
  }

  void _scheduleRecomputation() {
    if (!_hasScheduledRecomputation) {
      _hasScheduledRecomputation = true;
      scheduleMicrotask(_recompute);
    }
  }

  T _recompute() {
    _hasScheduledRecomputation = false;
    final updatedValue = compute(_computableValues);
    add(updatedValue);
    return updatedValue;
  }

  @override
  dispose() {
    super.dispose();
    for (final subscription in _subscriptions) {
      subscription.cancel();
    }
  }

  /// Since this is a hot observable, if there isn't a pending rebroadcast, then it has the latest updated value already
  /// and that value can be immediately returned without recomputation. If there is a pending recomputation scheduled, then we must
  /// recompute immediately to return the latest value.
  @override
  get() {
    if (_hasScheduledRecomputation) {
      return _recompute();
    }
    return _value;
  }
}
