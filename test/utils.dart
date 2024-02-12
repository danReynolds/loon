import 'dart:async';

/// A type of completer that is reset after its current completion result is observed by a subscriber
/// to its future.
class ResetCompleter<T> {
  Completer<T> _completer = Completer();

  void complete([T? value]) {
    _completer.complete(value);
  }

  Future<void> get future async {
    await _completer.future;
    _completer = Completer<T>();
  }
}
