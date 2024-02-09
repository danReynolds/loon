part of loon;

typedef SerializedCollectionStore = Map<String, Map<String, Json>>;

class PersistorSettings<T> {
  final bool persistenceEnabled;

  const PersistorSettings({
    this.persistenceEnabled = true,
  });
}

abstract class Persistor {
  /// The documents broadcast for persistence are batched together while throttling persistence.
  /// This is necessary since multiple broadcast calls could occur within the throttle
  /// duration and all those documents should be combined into a single batch that executes when the throttle expires.
  final Map<String, BroadcastDocument> _batch = {};
  Timer? _persistTimer;
  bool _isPersisting = false;
  final Duration persistenceThrottle;

  final PersistorSettings persistorSettings;

  Persistor({
    this.persistorSettings = const PersistorSettings(),
    this.persistenceThrottle = const Duration(milliseconds: 100),
  });

  Future<void> _persist() async {
    _isPersisting = true;

    try {
      final batchDocs = _batch.values.toList();

      // The current batch is eagerly cleared so that after persistence completes, it can be re-checked to see if there
      // are more documents to persist and schedule another run.
      _batch.clear();

      await persist(batchDocs);
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

  /// When the persistor receives a broadcast event, it batches the applicable broadcast documents
  /// and schedules a persistence if necessary.
  void onBroadcast(List<BroadcastDocument> broadcastDocs) {
    // Certain types of broadcasts do not need to be persisted:
    // 1. Touched documents do not need to be re-persisted since their data has not changed.
    // 2. Hydrated documents do not need to be re-persisted since their data just came from persistence.
    final docs = broadcastDocs
        .where((broadcastDoc) =>
            broadcastDoc.type != BroadcastEventTypes.touched &&
            broadcastDoc.type != BroadcastEventTypes.hydrated)
        .toList();

    if (docs.isEmpty) {
      return;
    }

    // Since multiple broadcasts can occur within the persistence throttle, documents are batched together
    // into a single batch that are persisted together when persistence is executed.
    for (final doc in docs) {
      _batch[doc.path] = doc;
    }

    _schedulePersist();
  }

  Future<void> persist(List<BroadcastDocument> docs);

  Future<SerializedCollectionStore> hydrate();

  Future<void> clear(String collection);

  Future<void> clearAll();
}
