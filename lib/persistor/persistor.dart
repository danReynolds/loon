part of loon;

typedef SerializedCollectionStore = Map<String, Map<String, Json>>;

class PersistorSettings<T> {
  final bool persistenceEnabled;

  const PersistorSettings({
    this.persistenceEnabled = true,
  });
}

/// Abstract persistor that implements the base persistence batching, de-duping and locking of
/// persistence operations and exposes the public persistence APIs for persistence implementations to implement.
/// See [FilePersistor] as an example implementation.
abstract class Persistor {
  final Duration persistenceThrottle;
  final PersistorSettings persistorSettings;
  final void Function(List<Document> batch)? onPersist;
  final void Function()? onClear;
  final void Function(SerializedCollectionStore data)? onHydrate;

  final Set<Document> _batch = {};

  /// The operation queue ensures that operations (init, hydrate, persist, clear) are blocking and
  /// that only one is ever running at a time, not concurrently.
  final List<Completer> _operationQueue = [];

  Timer? _persistTimer;

  /// Whether the persistor is busy running an operation.
  bool _isBusy = false;

  Persistor({
    this.persistorSettings = const PersistorSettings(),
    this.persistenceThrottle = const Duration(milliseconds: 100),
    this.onPersist,
    this.onClear,
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

  Future<void> _clear() {
    return _runOperation(() async {
      await clear();
      onClear?.call();
    });
  }

  Future<SerializedCollectionStore> _hydrate() {
    return _runOperation(() async {
      final result = await hydrate();
      onHydrate?.call(result);
      return result;
    });
  }

  Future<void> _persist() async {
    try {
      _runOperation(() async {
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
    _persistTimer ??= Timer(persistenceThrottle, () {
      _persist();
    });
  }

  void _persistDoc(Document doc) {
    if (!doc.isPersistenceEnabled()) {
      printDebug('Persistence not enabled for document: ${doc.id}');
      return;
    }

    if (_batch.contains(doc)) {
      return;
    }

    _batch.add(doc);
    _schedulePersist();
  }

  /// Public APIs to be implemented by any [Persistor] extension like [FilePersistor].

  Future<void> init();

  Future<void> persist(List<Document> docs);

  Future<SerializedCollectionStore> hydrate();

  Future<void> clear();
}
