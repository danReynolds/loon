part of 'loon.dart';

class ComputedStream<T> with Computable<T>, Observable<T> {
  final Stream<T> sourceStream;
  late final StreamSubscription<T> _sourceStreamSubscription;

  ComputedStream(
    this.sourceStream, {
    T? initialValue,
    bool multicast = false,
  }) {
    assert(
      initialValue != null || T == Optional<T>,
      'ComputedStream must specify a nullable type or an initial value.',
    );

    _sourceStreamSubscription = sourceStream.listen(
      (value) => add(value),
      onDone: () {
        dispose();
      },
    );

    init(initialValue as T, multicast: multicast);
  }

  @override
  dispose() {
    super.dispose();
    _sourceStreamSubscription.cancel();
  }

  @override
  get() {
    return _value;
  }

  @override
  observe({
    bool multicast = false,
  }) {
    return this;
  }
}
