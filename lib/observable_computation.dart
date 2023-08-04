part of 'loon.dart';

class ObservableComputation<T> extends Computation<T> with Observable<T> {
  final List<StreamSubscription> _subscriptions = [];
  List computableValues = [];

  ObservableComputation({
    required super.initialValue,
    required super.computables,
    required super.compute,
  }) {
    for (int i = 0; i < computables.length; i++) {
      _subscriptions.add(
        computables[i].stream().listen(
          (inputValue) {
            computableValues[i] = inputValue;
            add(compute(computableValues));
          },
        ),
      );
    }
  }
}
