part of loon;

abstract class PersistorSettings<T> {}

abstract class Persistor {
  final BroadcastCollectionDataStore _broadcastCollectionDataStore = {};
  Timer? _persistTimer;
  bool _isPersisting = false;

  final Duration persistenceThrottle;

  Persistor({
    this.persistenceThrottle = const Duration(milliseconds: 100),
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
      _persistTimer = Timer(persistenceThrottle, () {
        _persistTimer = null;
        _persist();
      });
    }

    for (final doc in docs) {
      final docId = doc.id;
      final collection = doc.collection;

      if (!_broadcastCollectionDataStore.containsKey(collection)) {
        _broadcastCollectionDataStore[collection] = {};
      }

      _broadcastCollectionDataStore[collection]![docId] = doc;
    }
  }

  Future<void> persist(List<BroadcastDocument> docs);

  Future<CollectionDataStore> hydrate();

  Future<void> clear(String collection);
}
