part of '../loon.dart';

abstract class PersistorOperation<T> {
  final _completer = Completer<T>();

  void complete(T data) {
    _completer.complete(data);
  }

  void error(Object error) {
    _completer.completeError(error);
  }

  Future<T> get onComplete {
    return _completer.future;
  }
}

abstract class PersistorBatchOperation<S, T> extends PersistorOperation<T> {
  final LinkedHashSet<S> batch;

  PersistorBatchOperation(this.batch);
}

class InitOperation extends PersistorOperation<void> {}

class PersistOperation
    extends PersistorBatchOperation<Document, LinkedHashSet<Document>> {
  PersistOperation(super.batch);
}

class ClearOperation
    extends PersistorBatchOperation<Collection, LinkedHashSet<Collection>> {
  ClearOperation(super.batch);
}

class HydrateOperation extends PersistorBatchOperation<StoreReference, Json> {
  HydrateOperation(super.batch);
}

class HydrateAllOperation extends PersistorOperation<Json> {}

class ClearAllOperation extends PersistorOperation<void> {}
