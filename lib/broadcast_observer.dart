part of loon;

mixin BroadcastObserver<T> on Observable<T> {
  @override
  void init(
    T initialValue, {
    required bool multicast,
  }) {
    super.init(initialValue, multicast: multicast);
    Loon._instance._addBroadcastObserver(this);
  }

  @override
  void dispose() {
    super.dispose();
    Loon._instance._removeBroadcastObserver(this);
  }

  void _onBroadcast();
}