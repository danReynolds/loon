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

class PersistorCompleter {
  final _onPersistCompleter = ResetCompleter();
  final _onClearCompleter = ResetCompleter();

  void persistComplete() {
    _onPersistCompleter.complete();
  }

  void clearComplete() {
    _onClearCompleter.complete();
  }

  Future<void> get onPersistComplete {
    return _onPersistCompleter.future;
  }

  Future<void> get onClearComplete {
    return _onClearCompleter.future;
  }
}
