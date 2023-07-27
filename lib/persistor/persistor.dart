part of loon;

typedef SerializedCollectionStore = Map<String, Map<String, Json>>;

class PersistorSettings<T> {
  final Duration persistenceThrottle;
  final bool persistenceEnabled;

  const PersistorSettings({
    this.persistenceThrottle = const Duration(milliseconds: 100),
    this.persistenceEnabled = true,
  });
}

abstract class Persistor {
  final BroadcastCollectionStore _broadcastCollectionDataStore = {};
  Timer? _persistTimer;
  bool _isPersisting = false;

  final PersistorSettings persistorSettings;

  Persistor({
    this.persistorSettings = const PersistorSettings(),
  });

  List<BroadcastDocument> get _pendingDocuments {
    final collectionDataStores = _broadcastCollectionDataStore.values;

    return collectionDataStores.fold<List<BroadcastDocument>>([],
        (acc, collection) {
      return [
        ...acc,
        ...collection.values,
      ];
    });
  }

  Future<void> _persist() async {
    // A guard to prevent multiple persistence calls from stacking up in the scenario where
    // persistence takes longer than the throttle.
    if (_isPersisting) {
      return;
    }
    _isPersisting = true;

    final docs = _pendingDocuments;
    if (docs.isEmpty) {
      return;
    }

    // The collection data stores are eagerly cleared after their documents are sent to be persisted.
    for (final collectionDataStore in _broadcastCollectionDataStore.values) {
      collectionDataStore.clear();
    }

    try {
      await persist(docs);
    } finally {
      _isPersisting = false;

      // On persist completing, if there are more docs that have since been added to be persisted,
      // then persist again.
      if (_pendingDocuments.isNotEmpty) {
        _persist();
      }
    }
  }

  void onBroadcast(List<BroadcastDocument> docs) {
    if (docs.isEmpty) {
      return;
    }

    if (_persistTimer == null && !_isPersisting) {
      _persistTimer = Timer(persistorSettings.persistenceThrottle, () {
        _persistTimer = null;
        _persist();
      });
    }

    for (final doc in docs) {
      final docId = doc.id;
      final path = doc.path;

      if (!_broadcastCollectionDataStore.containsKey(path)) {
        _broadcastCollectionDataStore[path] = {};
      }

      _broadcastCollectionDataStore[path]![docId] = doc;
    }
  }

  Future<void> persist(List<BroadcastDocument> docs);

  Future<SerializedCollectionStore> hydrate();

  Future<void> clear(String collection);

  Future<void> clearAll();
}
