part of loon;

/// Extends an [Observable] by registering it to receive document broadcasts.
mixin BroadcastObserver<T> on Observable<T> {
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
