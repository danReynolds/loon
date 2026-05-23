import 'dart:async';

class Lock {
  Completer? _completer;

  Future<void> acquire() async {
    // Multiple waiters can be parked on the same completer, so each must
    // re-check on wake — only one gets to install the next completer.
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
