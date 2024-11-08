import 'dart:async';

/// A type of completer that is reset after its current completion result is observed by a subscriber
/// to its future.
class _ResetCompleter<T> {
  Completer<T> _completer = Completer();

  void complete([T? value]) {
    if (!_completer.isCompleted) {
      _completer.complete(value);
    }
  }

  Future<void> get future async {
    await _completer.future;
    _completer = Completer<T>();
  }
}

class TestPersistCompleter {
  final _onPersistCompleter = _ResetCompleter();
  final _onClearCompleter = _ResetCompleter();
  final _onHydrateCompleter = _ResetCompleter();
  final _onClearAllCompleter = _ResetCompleter();
  final _onSyncCompleter = _ResetCompleter();

  void persistComplete() {
    _onPersistCompleter.complete();
  }

  void clearComplete() {
    _onClearCompleter.complete();
  }

  void clearAllComplete() {
    _onClearAllCompleter.complete();
  }

  void hydrateComplete() {
    _onHydrateCompleter.complete();
  }

  void syncComplete() {
    _onSyncCompleter.complete();
  }

  Future<void> get onPersist {
    return _onPersistCompleter.future;
  }

  Future<void> get onClear {
    return _onClearCompleter.future;
  }

  Future<void> get onClearAll {
    return _onClearAllCompleter.future;
  }

  Future<void> get onHydrate {
    return _onHydrateCompleter.future;
  }

  Future<void> get onSync {
    return _onSyncCompleter.future;
  }
}
