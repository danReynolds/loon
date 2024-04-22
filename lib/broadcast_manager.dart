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
  final store = ValueStore<EventTypes>();

  /// The store of broadcast observers that should be notified on broadcast
  final Set<BroadcastObserver> _observers = {};

  /// Whether the broadcast store is dirty and has a pending broadcast scheduled.
  bool _pendingBroadcast = false;

  void _scheduleBroadcast() {
    if (!_pendingBroadcast) {
      _pendingBroadcast = true;

      // Schedule a broadcast event to be run on the microtask queue. The broadcast is run
      // async so that multiple broadcast events can be batched together into one update
      // across all changes that occur in the current task of the event loop.
      scheduleMicrotask(() {
        for (final observer in _observers) {
          observer._onBroadcast();
        }
        store.clear();
        _pendingBroadcast = false;
      });
    }
  }

  void _writePath(String path, EventTypes event) {
    final pendingEvent = store.get(path);

    // Ignore writing a duplicate event type or overwriting a pending mutative event type with a touched event.
    if (pendingEvent != null &&
        (pendingEvent == event || pendingEvent == EventTypes.touched)) {
      return;
    }

    store.write(path, event);
  }

  void writeDocument(Document doc, EventTypes event) {
    _writePath(doc.path, event);

    // If this is the first document written to the collection, then add a [EventTypes.added]
    // event for the collection path.
    if (!Loon._instance.documentStore.hasAny(doc.parent)) {
      _writePath(doc.parent, EventTypes.added);
    }

    broadcastDependents(doc);

    _scheduleBroadcast();
  }

  /// Schedules all dependents of the given document for broadcast.
  void broadcastDependents(Document doc) {
    final dependents = Loon._instance.dependentsStore[doc];

    if (dependents != null) {
      for (final doc in dependents.toList()) {
        // If a dependent does not exist in the store, then it is lazily removed.
        if (!doc.exists()) {
          dependents.remove(doc);
        } else {
          writeDocument(doc, EventTypes.touched);
        }
      }
    }
  }

  /// When a path is deleted from the document store, the broadcast store is updated
  /// to remove all broadcasts scheduled for that path and paths under it, since that subtree
  /// is now invalid, and replace the root of the subtree with a single [EventTypes.removed] event for that path.
  ///
  /// If any observer's dependencies contain the deleted path, then the observer must
  /// be scheduled for rebroadcast, since its dependencies are dirty.
  void _deletePath(String path) {
    store.delete(path);
    store.write(path, EventTypes.removed);

    for (final observer in _observers) {
      if (observer._deps.hasPath(path)) {
        store.write(observer.path, EventTypes.touched);
      }
    }

    _scheduleBroadcast();
  }

  void deleteCollection(Collection collection) {
    _deletePath(collection.path);
  }

  void deleteDocument(Document doc) {
    _deletePath(doc.path);
    broadcastDependents(doc);
  }

  void clear() {
    store.clear();
    _scheduleBroadcast();
  }

  void addObserver(BroadcastObserver observer) {
    _observers.add(observer);
  }

  void removeObserver(BroadcastObserver observer) {
    _observers.remove(observer);
  }

  Map inspect() {
    return store.inspect();
  }
}
