part of loon;

typedef HydrationData = Map<String, Json>;

class PersistorSettings<T> {
  final bool enabled;
  final Duration persistenceThrottle;

  const PersistorSettings({
    this.enabled = true,
    this.persistenceThrottle = const Duration(milliseconds: 100),
  });
}

/// Abstract persistor that implements the base persistence batching, de-duping and locking of
/// persistence operations. Exposes the public persistence APIs for persistence implementations to implement.
/// See [FilePersistor] as an example implementation.
abstract class Persistor {
  final PersistorSettings settings;
  final void Function(List<Document> batch)? onPersist;
  final void Function(Collection collection)? onClear;
  final void Function()? onClearAll;
  final void Function(HydrationData data)? onHydrate;

  final Set<Document> _batch = {};

  final _logger = Logger('Persistor');

  /// The operation queue ensures that operations (init, hydrate, persist, clear) are blocking and
  /// that only one is ever running at a time, not concurrently.
  final List<Completer> _operationQueue = [];

  Timer? _persistTimer;

  /// Whether the persistor is busy running an operation.
  bool _isBusy = false;

  Persistor({
    this.settings = const PersistorSettings(),
    this.onPersist,
    this.onClear,
    this.onClearAll,
    this.onHydrate,
  }) {
    _runOperation(() {
      return init();
    });
  }

  Future<T> _runOperation<T>(Future<T> Function() operation) async {
    if (_isBusy) {
      final completer = Completer();
      _operationQueue.add(completer);
      await completer.future;
    } else {
      _isBusy = true;
    }

    try {
      // If the operation fails, then we still move on to the next operation. If it was a persist(),
      // then it can still be recovered, as the file data store will remain marked as dirty and will attempt
      // to be persisted again with the next persistence operation.
      final result = await operation();
      return result;
    } finally {
      // Start the next operation after the previous one completes.
      if (_operationQueue.isNotEmpty) {
        final completer = _operationQueue.removeAt(0);
        completer.complete();
      } else {
        _isBusy = false;
      }
    }
  }

  Future<void> _clear(Collection collection) {
    return _runOperation(() async {
      await clear(collection);
      onClear?.call(collection);
    });
  }

  Future<void> _clearAll() {
    return _runOperation(() async {
      await clearAll();
      onClearAll?.call();
    });
  }

  Future<HydrationData> _hydrate([List<Collection>? collections]) {
    return _runOperation(() async {
      final result = await hydrate(collections);
      onHydrate?.call(result);
      return result;
    });
  }

  Future<void> _persist() async {
    try {
      await _runOperation(() async {
        final batchDocs = _batch.toList();

        // The current batch is eagerly cleared so that after persistence completes, it can be re-checked to see if there
        // are more documents to persist and schedule another run.
        _batch.clear();

        await persist(batchDocs);

        onPersist?.call(batchDocs);
      });
    } finally {
      _persistTimer = null;

      // If there are more documents that came in while the previous batch was being persisted, then schedule another persist.
      if (_batch.isNotEmpty) {
        _schedulePersist();
      }
    }
  }

  /// Schedules the current batch of documents to be persisted using a timer set to the persistence throttle.
  void _schedulePersist() {
    _persistTimer ??= Timer(settings.persistenceThrottle, () {
      _persist();
    });
  }

  void _persistDoc(Document doc) {
    if (!doc.isPersistenceEnabled()) {
      _logger.log('Persistence not enabled for document: ${doc.id}');
      return;
    }

    if (_batch.contains(doc)) {
      return;
    }

    _batch.add(doc);
    _schedulePersist();
  }

  ///
  /// Public APIs to be implemented by any [Persistor] extension like [FilePersistor].
  ///

  /// Initialization function called when the persistor is instantiated to execute and setup work.
  Future<void> init();

  /// Persist function called with the list of documents that have changed (including been deleted).
  Future<void> persist(List<Document> docs);

  /// Hydration function called to read data from persistence. If no collections are specified,
  /// then it hydrations all persisted data. if collections are specified, it hydrates only the data from those
  /// collections and their subcollections.
  Future<HydrationData> hydrate([List<Collection>? collections]);

  /// Clear function used to clear all documents in a collection.
  Future<void> clear(Collection collection);

  /// Clears all documents and removes all persisted data.
  Future<void> clearAll();
}
