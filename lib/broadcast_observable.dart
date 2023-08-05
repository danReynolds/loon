part of loon;

/// A [BroadcastObservable] is an extension of the [Observable] mixin that adds support
/// for receiving [Document] broadcasts.
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
