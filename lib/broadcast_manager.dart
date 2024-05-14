part of loon;

enum BroadcastEvents {
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
  /// The store of documents/collections scheduled for broadcast.
  final store = IndexedValueStore<BroadcastEvents>();

  /// The store of broadcast observers that should be notified on broadcast.
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

  /// Schedules all dependents of the given document for broadcast.
  void _broadcastDependents(Document doc) {
    final dependents = Loon._instance.dependentsStore[doc];

    if (dependents != null) {
      for (final doc in dependents.toList()) {
        // If a dependent document does not exist in the store, then it is lazily removed.
        if (!doc.exists()) {
          dependents.remove(doc);
        } else if (!store.hasValue(doc.path)) {
          writeDocument(doc, BroadcastEvents.touched);
        }
      }

      if (dependents.isEmpty) {
        Loon._instance.dependentsStore.remove(doc);
      }
    }
  }

  void _writePath(String path, BroadcastEvents event) {
    final pendingEvent = store.get(path);

    // Ignore writing a duplicate event type or overwriting a pending mutative event type with a touched event.
    if (pendingEvent != null &&
        (pendingEvent == event || pendingEvent == BroadcastEvents.touched)) {
      return;
    }

    store.write(path, event);

    _scheduleBroadcast();
  }

  /// Deletes the given path from the broadcast store.
  void _delete(String path) {
    /// When a path is deleted, the broadcast store is updated to remove all broadcast events
    /// scheduled for that path and its subtree and replaces the root of that broadcast store path
    /// with a single removed event.
    store.delete(path);
    store.write(path, BroadcastEvents.removed);

    /// Deleting paths should be infrequent, so iterating over every active observer for each delete
    /// is presumed to be reasonable for performance, given the small number of deletions and observers.
    for (final observer in _observers) {
      // If the observer's path is a child of the deleted path, then the observer is rebroadcast
      // as having been removed.
      if (observer.exists() && observer.path.startsWith(path)) {
        store.write(observer.path, BroadcastEvents.removed);

        /// If any observer's dependencies contain the deleted path, then the observer must
        /// be scheduled for rebroadcast, since its dependencies are dirty.
      } else if (observer._deps.has(path)) {
        store.write(observer.path, BroadcastEvents.touched);
      }
    }

    _scheduleBroadcast();
  }

  void writeDocument(Document doc, BroadcastEvents event) {
    _writePath(doc.path, event);
    _broadcastDependents(doc);
  }

  void deleteCollection(Collection collection) {
    _delete(collection.path);
  }

  void deleteDocument(Document doc) {
    _delete(doc.path);

    _broadcastDependents(doc);
  }

  void clear() {
    store.clear();

    for (final observer in _observers) {
      _writePath(observer.path, BroadcastEvents.removed);
    }
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
