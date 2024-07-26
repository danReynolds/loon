import 'dart:async';

class ThrottleCanceledException implements Exception {}

class Throttler {
  final Duration duration;
  final Future<void> Function() callback;

  Throttler(this.duration, this.callback);

  Timer? _timer;
  Completer? _completer;

  /// Executes the callback after the current timer has completed. If the throttle
  /// timer is in progress, it waits out the remainder of that timer. Otherwise
  /// it creates a new timer and awaits the full throttle duration.
  Future<void> run() async {
    if (_timer == null) {
      print('here');
      final completer = _completer = Completer();
      _timer = Timer(duration, _complete);
      return completer.future;
    }

    return _completer!.future;
  }

  Future<void> _complete() async {
    if (_completer != null) {
      try {
        await callback();
        _completer!.complete();
      } catch (e) {
        _completer!.completeError(e);
      } finally {
        _timer = null;
        _completer = null;
      }
    }
  }

  /// Cancels an ongoing timer.
  void cancel() {
    _timer?.cancel();
    _completer?.completeError(ThrottleCanceledException());
  }

  /// Completes the throttle early, immediately executing the callback.
  Future<void> complete() {
    _timer?.cancel();
    return _complete();
  }
}
