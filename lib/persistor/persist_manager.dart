part of loon;

class PersistManager {
  /// The operation queue is used to sequence persistor operations (init, hydrate, persist, clear, clearAll)
  /// in order to prevent race conditions and ensure operations are executed in the correct order.
  final List<PersistorOperation> _operationQueue = [];

  final Persistor persistor;

  late final Logger _logger;

  bool _isBusy = false;

  PersistManager({
    required this.persistor,
  }) : _logger = Logger('PersistManager', output: Loon.logger.log) {
    _enqueue(InitOperation());
  }

  Future<void> _next<T>() async {
    if (_operationQueue.isEmpty || _isBusy) {
      return;
    }

    _isBusy = true;
    final current = _operationQueue.first;

    // The operation is delayed a moment so that consecutive operations of the same type
    // (multiple persist, clear, hydrate operations) can be batched together into a single
    // operation.
    await Future.delayed(const Duration(milliseconds: 1));
    _operationQueue.removeAt(0);

    try {
      switch (current) {
        case InitOperation():
          await persistor.init();
          current.complete(null);
          break;
        case PersistOperation(batch: final docs):
          await persistor.persist(docs.toList());
          current.complete(docs);
          persistor.onPersist?.call(docs);
          break;
        case ClearOperation(batch: final collections):
          await persistor.clear(collections.toList());
          current.complete(collections);
          persistor.onClear?.call(collections);
          break;
        case HydrateOperation(batch: final refs):
          final data = await persistor.hydrate(refs.toList());
          current.complete(data);
          persistor.onHydrate?.call(data);
          break;
        case HydrateAllOperation():
          final data = await persistor.hydrate();
          current.complete(data);
          persistor.onHydrate?.call(data);
          break;
        case ClearAllOperation():
          await persistor.clearAll();
          current.complete(null);
          persistor.onClearAll?.call();
          break;
      }
    } catch (e) {
      current.error(e);
    } finally {
      _isBusy = false;
      if (_operationQueue.isNotEmpty) {
        _next();
      }
    }
  }

  Future<T> _enqueue<T>(PersistorOperation<T> operation) {
    _operationQueue.add(operation);
    _next();
    return operation.onComplete;
  }

  PersistorSettings get settings {
    return persistor.settings;
  }

  Future<Set<Document>> persist(Document doc) async {
    if (!doc.isPersistenceEnabled()) {
      _logger.log('Persistence not enabled for document: ${doc.id}');
      return <Document>{};
    }

    final lastOperation = _operationQueue.tryLast;
    if (lastOperation is PersistOperation) {
      final batch = lastOperation.batch;

      // The batch could already contain this document with a different configuration
      // (fromJson, toJson, etc). In this case, the old document should be removed and replaced
      // with the updated one.
      if (batch.contains(doc)) {
        batch.remove(doc);
      }
      batch.add(doc);
      return lastOperation.onComplete;
    }

    return _enqueue(PersistOperation(LinkedHashSet.of([doc])));
  }

  Future<void> clear(Collection collection) {
    final lastOperation = _operationQueue.tryLast;
    if (lastOperation is ClearOperation) {
      lastOperation.batch.add(collection);
      return lastOperation.onComplete;
    }

    return _enqueue(ClearOperation(LinkedHashSet.of([collection])));
  }

  Future<void> clearAll() {
    final lastOperation = _operationQueue.tryLast;
    if (lastOperation is ClearAllOperation) {
      return lastOperation.onComplete;
    }

    return _enqueue(ClearAllOperation());
  }

  Future<Json> hydrate([List<StoreReference>? refs]) {
    final lastOperation = _operationQueue.tryLast;

    if (refs == null) {
      if (lastOperation is HydrateAllOperation) {
        return lastOperation.onComplete;
      }
      return _enqueue(HydrateAllOperation());
    }

    if (lastOperation is HydrateOperation) {
      lastOperation.batch.addAll(refs);
      return lastOperation.onComplete;
    }

    return _enqueue(HydrateOperation(LinkedHashSet.from(refs)));
  }
}
