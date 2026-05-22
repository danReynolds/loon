import 'dart:async';

class Lock {
  Completer? _completer;

  Future<void> acquire() async {
    // Loop so concurrent waiters re-check the lock state when they wake. Without
    // the loop, two waiters on the same completer would each install their own
    // and both think they hold the lock.
    while (_completer != null) {
      await _completer!.future;
    }

    _completer = Completer();
  }

  void release() {
    _completer?.complete();
    _completer = null;
  }

  Future<T> run<T>(Future<T> Function() callback) async {
    await acquire();
    try {
      final result = await callback();
      return result;
    } finally {
      release();
    }
  }
}
