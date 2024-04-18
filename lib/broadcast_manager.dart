part of loon;

enum EventTypes {
  /// The document has been modified.
  modified,

  /// The document has been added.
  added,

  /// The document has been removed.
  removed,

  /// The document has been manually touched for rebroadcast.
  touched,

  /// The document has been hydrated from persisted storage.
  hydrated,
}

class BroadcastManager {
  /// The store of broadcast documents/collections scheduled for broadcast.
  final StoreNode<EventTypes> _store = StoreNode();

  /// The store of broadcast observers that should be notified on broadcast.
  final Set<BroadcastObserver> _observers = {};

  /// Whether the broadcast store is dirty and has a pending broadcast scheduled.
  bool _pendingBroadcast = false;

  void scheduleBroadcast() {
    if (!_pendingBroadcast) {
      _pendingBroadcast = true;

      // Schedule a broadcast event to be run on the microtask queue. The broadcast is run
      // async so that multiple broadcast events can be batched together into one update
      // across all changes that occur in the current task of the event loop.
      scheduleMicrotask(() {
        for (final observer in _observers) {
          observer._onBroadcast();
        }
        _store.clear();
      });
    }
  }

  EventTypes? getBroadcast(Document doc) {
    return _store.get(doc.path);
  }

  Map<String, EventTypes>? getBroadcasts<T>(Collection collection) {
    return _store.getAll(collection.path);
  }

  bool contains(String path) {
    return _store.contains(path);
  }

  void writeDocument(Document doc, EventTypes event) {
    final pendingEvent = _store.get(doc.path);

    // Ignore writing a duplicate event type or overwriting a pending mutative event type with a touched event.
    if (pendingEvent != null &&
        (pendingEvent == event || pendingEvent == EventTypes.touched)) {
      return;
    }

    _store.write(doc.path, event);

    broadcastDependents(doc);

    scheduleBroadcast();
  }

  /// Schedules all dependents of the given document for broadcast.
  void broadcastDependents(Document doc) {
    final dependents = Loon._instance.dependentsStore.get(doc.path);

    if (dependents != null) {
      for (final dependent in dependents) {
        writeDocument(dependent, EventTypes.touched);
      }
    }
  }

  void deleteCollection(Collection collection) {
    _store.delete(collection.path);
    _store.write(collection.path, EventTypes.removed);
    scheduleBroadcast();
  }

  // On deleting a document, first delete any existing broadcast events for the document and documents *under* it,
  // as they are now invalid. Then write an event for the removal of the document to notify observers.
  void deleteDocument(Document doc) {
    _store.delete(doc.path);

    broadcastDependents(doc);

    scheduleBroadcast();
  }

  void clear() {
    _store.clear();
    scheduleBroadcast();
  }

  void addObserver(BroadcastObserver observer) {
    _observers.add(observer);
  }

  void removeObserver(BroadcastObserver observer) {
    _observers.remove(observer);
  }

  Map inspect() {
    return _store.inspect();
  }
}
