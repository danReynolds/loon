part of loon;

typedef SerializedCollectionStore = Map<String, Map<String, Json>>;

class PersistorSettings<T> {
  final bool persistenceEnabled;

  const PersistorSettings({
    this.persistenceEnabled = true,
  });
}

abstract class Persistor {
  final Duration persistenceThrottle;
  final PersistorSettings persistorSettings;
  final void Function(List<Document> batch)? onPersist;

  final Map<String, Document> _batch = {};

  Timer? _persistTimer;

  bool _isPersisting = false;

  final _initializedCompleter = Completer<void>();

  Persistor({
    this.persistorSettings = const PersistorSettings(),
    this.persistenceThrottle = const Duration(milliseconds: 100),
    this.onPersist,
  }) {
    _init();
  }

  Future<void> get _isInitialized {
    return _initializedCompleter.future;
  }

  Future<void> _init() async {
    await init();
    _initializedCompleter.complete();
  }

  Future<void> _clear(String collection) async {
    await _isInitialized;
    await clear(collection);
  }

  Future<void> _clearAll() async {
    await _isInitialized;
    await clearAll();
  }

  Future<SerializedCollectionStore> _hydrate() async {
    await _isInitialized;
    return hydrate();
  }

  Future<void> _persist() async {
    _isPersisting = true;

    try {
      final batchDocs = _batch.values.toList();

      // The current batch is eagerly cleared so that after persistence completes, it can be re-checked to see if there
      // are more documents to persist and schedule another run.
      _batch.clear();

      await _isInitialized;
      await persist(batchDocs);

      onPersist?.call(batchDocs);
    } finally {
      _isPersisting = false;

      // If there are more documents that came in while the previous batch was being persisted, then schedule another persist.
      if (_batch.isNotEmpty) {
        _schedulePersist();
      }
    }
  }

  /// Schedules the current batch of documents to be persisted using a timer set to the persistence throttle.
  void _schedulePersist() {
    if (_persistTimer == null && !_isPersisting) {
      _persistTimer = Timer(persistenceThrottle, () {
        _persistTimer = null;
        _persist();
      });
    }
  }

  void _persistDoc(Document doc) {
    if (_batch.containsKey(doc.path)) {
      return;
    }

    _batch[doc.path] = doc;
    _schedulePersist();
  }

  /// Public APIs to be implemented by any [Persistor] extension like [FilePersistor].

  Future<void> init();

  Future<void> persist(List<Document> docs);

  Future<SerializedCollectionStore> hydrate();

  Future<void> clear(String collection);

  Future<void> clearAll();
}
