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

/// The broadcast manager handles all logic related to the active broadcast observers.
/// Its functions include:
/// 1. Maintaining the set of active broadcast observers.
/// 2. Maintaining the event store of changes to deliver to observers on broadcast.
/// 3. Scheduling and firing the broadcast to observers.
/// 4. Maintaining the store of cached broadcast observer values.
class BroadcastManager {
  /// The store of documents/collections events scheduled for broadcast.
  final eventStore = ValueStore<BroadcastEvents>();

  /// The store of broadcast observer values.
  final observerValueStore = ValueStore();

  /// The set of broadcast observers that should be notified on broadcast.
  final Set<BroadcastObserver> _observers = {};

  /// The subset of broadcast observers from [_observers] with dependencies.
  final Set<BroadcastObserver> _depObservers = {};

  /// Whether the broadcast store is dirty and has a pending broadcast scheduled.
  bool _pendingBroadcast = false;

  void _scheduleBroadcast() {
    if (!_pendingBroadcast) {
      _pendingBroadcast = true;

      // The broadcast is run async so that multiple broadcast events can be batched
      // together into one update across all changes that occur in the current task of the event loop.
      Future.delayed(Duration.zero, _broadcast);
    }
  }

  void _broadcast() {
    _depObservers.clear();

    for (final observer in _observers.toList()) {
      observer._onBroadcast();

      // Recalculate the set of observers with dependencies after they process the broadcast
      // and update their dependency stores.
      if (!observer._deps.isEmpty) {
        _depObservers.add(observer);
      }
    }

    eventStore.clear();
    _pendingBroadcast = false;
  }

  /// Schedules all dependents of the given document for broadcast.
  void _broadcastDependents(Document doc) {
    final dependents = Loon._instance.dependencyManager.getDependents(doc);
    if (dependents != null) {
      for (final doc in dependents) {
        if (!eventStore.hasValue(doc.path)) {
          writeDocument(doc, BroadcastEvents.touched);
        }
      }
    }
  }

  void _deletePath(String path) {
    /// When a path is deleted, the event store is updated to remove all broadcast events
    /// scheduled for that path and its subtree and replaces the root of that broadcast store path
    /// with a single removed event.
    eventStore.delete(path);
    eventStore.write(path, BroadcastEvents.removed);

    // Deleting a path also invalidates all cached values under that path in the observer
    // value store recursively.
    observerValueStore.delete(path);

    /// Deleting a path is relatively infrequent, so iterating over the subset of active observers with dependencies
    /// is presumed to be reasonable for performance, given the small number of deletions and deps observers.
    for (final observer in _depObservers) {
      if (observer._deps.has(path)) {
        eventStore.write(observer._observerId, BroadcastEvents.touched);
      }
    }

    _scheduleBroadcast();
  }

  void writeDocument(Document doc, BroadcastEvents event) {
    final path = doc.path;

    if (event != BroadcastEvents.touched) {
      // All cached observer values for the document and its collection
      // are invalidated after the document is mutated.
      observerValueStore.delete(doc.path, recursive: false);
      observerValueStore.delete(doc.parent, recursive: false);
    }

    final pendingEvent = eventStore.get(path);
    // Ignore writing a duplicate events or overwriting a pending mutative event type with a touched event.
    if (pendingEvent == null ||
        (event != pendingEvent && event != BroadcastEvents.touched)) {
      eventStore.write(path, event);
    }

    _broadcastDependents(doc);
    _scheduleBroadcast();
  }

  void deleteCollection(Collection collection) {
    _deletePath(collection.path);
  }

  void deleteDocument(Document doc) {
    _deletePath(doc.path);

    // All cached observer values for the document's collection are also invalidated after
    // the document is deleted.
    observerValueStore.delete(doc.parent, recursive: false);

    _broadcastDependents(doc);
  }

  void clear() {
    eventStore.clear();
    observerValueStore.clear();

    for (final observer in _observers) {
      eventStore.write(observer.path, BroadcastEvents.removed);
    }

    _scheduleBroadcast();
  }

  void addObserver<T, S>(BroadcastObserver<T, S> observer, T initialValue) {
    _observers.add(observer);

    if (!observer._deps.isEmpty) {
      _depObservers.add(observer);
    }

    observerValueStore.write(observer._observerId, initialValue);
  }

  void removeObserver(BroadcastObserver observer) {
    _observers.remove(observer);
    _depObservers.remove(observer);

    observerValueStore.delete(observer._observerId);
  }

  void unsubscribe() {
    for (final observer in _observers.toList()) {
      observer.dispose();
    }
    _observers.clear();
    _depObservers.clear();
    observerValueStore.clear();
  }

  Map inspect() {
    return {
      "events": eventStore.inspect(),
      "observerValues": observerValueStore.inspect(),
    };
  }
}
