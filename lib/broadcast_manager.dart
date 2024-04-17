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

  EventTypes? getBroadcast(Document doc) {
    return _store.get(doc.path);
  }

  Map<String, EventTypes>? getBroadcasts<T>(Collection collection) {
    return _store.getAll(collection.path);
  }

  bool contains(String path) {
    return _store.contains(path);
  }

  void write(String path, EventTypes event) {
    final pendingEvent = _store.get(path);

    // Ignore writing a duplicate event type or overwriting a pending mutative event type with a touched event.
    if (pendingEvent != null &&
        (pendingEvent == event || pendingEvent == EventTypes.touched)) {
      return;
    }

    _store.write(path, event);
  }

  void delete(String path) {
    _store.delete(path);

    // Notify all observers watching documents of the collection ands its subcollections
    // that they have been cleared. Given the sparse number of active observers relative to documents,
    // this should be relatively performant.
    for (final observer in _observers) {
      if (observer.path.startsWith(path)) {
        observer._onClear();
      }
    }
  }

  void clear() {
    _store.clear();

    for (final observer in _observers) {
      observer._onClear();
    }
  }

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
