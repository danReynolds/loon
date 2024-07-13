part of loon;

class PersistenceScheduler {
  /// The operation queue is used to sequence persistor operations (init, hydrate, persist, clear, clearAll)
  /// in order to prevent race conditions and ensure operations are executed in the correct order.
  final List<PersistorOperation> _operationQueue = [];

  final Persistor _persistor;

  late final Logger _logger;

  bool _isBusy = false;

  PersistenceScheduler({
    required Persistor persistor,
  })  : _persistor = persistor,
        _logger = Logger('Persistor', output: Loon.logger.log);

  Future<void> _next<T>() async {
    if (_operationQueue.isEmpty || _isBusy) {
      return;
    }

    _isBusy = true;
    final current = _operationQueue.first;

    // An operation delays execution until its execution window is expired so that it
    // can de-dupe redundant operations.
    //
    // For example, if many documents are written in succession within a persistence throttle window,
    // they are de-duped into a single persistence operation. The default throttle for this is 100ms.
    if (!current.isExpired) {
      await current.onExpire;
    }
    _operationQueue.removeAt(0);

    try {
      switch (current) {
        case InitOperation():
          await _persistor.init();
          current.complete(null);
          break;
        case PersistOperation(batch: final docs):
          await _persistor.persist(docs);
          current.complete(docs);
          _persistor.onPersist?.call(docs);
          break;
        case ClearOperation(batch: final collections):
          await _persistor.clear(collections);
          current.complete(collections);
          _persistor.onClear?.call(collections);
          break;
        case HydrateOperation(batch: final refs):
          final data = await _persistor.hydrate(refs);
          current.complete(data);
          _persistor.onHydrate?.call(data);
          break;
        case ClearAllOperation():
          await _persistor.clearAll();
          current.complete(null);
          _persistor.onClearAll?.call();
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

  Future<T> _schedule<T>(PersistorOperation<T> operation) {
    _operationQueue.add(operation);
    _next();
    return operation.onComplete;
  }

  PersistorSettings get settings {
    return _persistor.settings;
  }

  Future<Set<Document>> persist(Document doc) async {
    if (!doc.isPersistenceEnabled()) {
      _logger.log('Persistence not enabled for document: ${doc.id}');
      return <Document>{};
    }

    final lastOperation = _operationQueue.tryLast;
    if (lastOperation is PersistOperation && !lastOperation.isExpired) {
      lastOperation.batch.add(doc);
      return lastOperation.onComplete;
    }

    return _schedule(
      PersistOperation(
        batch: {doc},
        // Persistence batches changes together using an extended window specified
        // by the client. By default it is set to 100ms.
        expiration: _persistor.persistenceThrottle,
      ),
    );
  }

  Future<void> clear(Collection collection) {
    final lastOperation = _operationQueue.tryLast;
    if (lastOperation is ClearOperation) {
      lastOperation.batch.add(collection);
      _next();

      return lastOperation.onComplete;
    }

    return _schedule(ClearOperation(batch: {collection}));
  }

  Future<void> clearAll() {
    final lastOperation = _operationQueue.tryLast;
    if (lastOperation is ClearAllOperation) {
      return lastOperation.onComplete;
    }

    return _schedule(ClearAllOperation());
  }

  Future<HydrationData> hydrate([Set<StoreReference>? refs]) {
    final lastOperation = _operationQueue.tryLast;

    if (refs == null) {
      if (lastOperation is HydrateAllOperation) {
        return lastOperation.onComplete;
      }
      return _schedule(HydrateAllOperation());
    }

    if (lastOperation is HydrateOperation) {
      lastOperation.batch.addAll(refs);
      return lastOperation.onComplete;
    }

    return _schedule(HydrateOperation(batch: refs));
  }
}
