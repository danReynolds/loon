part of loon;

/// A mixin that extends the [Observable] implementation to support receiving document broadcasts.
mixin BroadcastObservable<T> on Observable<T> {
  @override
  void init(T initialValue) {
    super.init(initialValue);
    Loon._instance._addBroadcastObserver(this);
  }

  @override
  void dispose() {
    super.dispose();
    Loon._instance._removeBroadcastObserver(this);
  }

  void _onBroadcast();
}
