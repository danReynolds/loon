import 'dart:async';

class Lock {
  Completer? _completer;

  Future<void> acquire() async {
    Completer? completer = _completer;

    if (completer != null) {
      await completer.future;
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
