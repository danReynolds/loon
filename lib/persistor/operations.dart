part of loon;

abstract class PersistorOperation<T> {
  PersistorOperation({
    /// The execution window of the persistor operation. A persist operation has a default
    /// execution window of 100ms, while other operations default to 1ms in order to de-dupe
    /// successive operations within the same task.
    Duration expiration = const Duration(milliseconds: 1),
  }) {
    Future.delayed(expiration, _expirationCompleter.complete);
  }

  final _completer = Completer<T>();

  final _expirationCompleter = Completer<void>();

  void complete(T data) {
    _completer.complete(data);
  }

  void error(Object error) {
    _completer.completeError(error);
  }

  Future<T> get onComplete {
    return _completer.future;
  }

  Future<void> get onExpire {
    return _expirationCompleter.future;
  }

  bool get isExpired {
    return _expirationCompleter.isCompleted;
  }
}

abstract class PersistorBatchOperation<S, T> extends PersistorOperation<T> {
  final Set<S> batch = {};

  PersistorBatchOperation({
    super.expiration,
    Set<S>? batch,
  }) {
    if (batch != null) {
      this.batch.addAll(batch);
    }
  }
}

class InitOperation extends PersistorOperation<void> {}

class PersistOperation
    extends PersistorBatchOperation<Document, Set<Document>> {
  PersistOperation({
    super.batch,
    super.expiration,
  });
}

class ClearOperation
    extends PersistorBatchOperation<Collection, Set<Collection>> {
  ClearOperation({
    super.batch,
    super.expiration,
  });
}

class HydrateOperation
    extends PersistorBatchOperation<StoreReference, HydrationData> {
  HydrateOperation({
    super.batch,
    super.expiration,
  });
}

class HydrateAllOperation extends PersistorOperation<HydrationData> {}

class ClearAllOperation extends PersistorOperation<void> {}
