part of './loon.dart';

enum BroadcastEvents {
  /// The document has been modified.
  modified,

  /// The document has been added.
  added,

  /// The document has been removed.
  removed,

  /// The document has been touched: its observers re-read it and the queries on its collection
  /// re-evaluate it, either manually through [Document.rebroadcast] or because a document it
  /// depends on was written or deleted.
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

  /// The set of broadcast observers that should be notified on broadcast. Observers are tracked
  /// by identity, since observable documents compare equal to the documents they observe.
  final Set<BroadcastObserver> _observers = LinkedHashSet.identity();

  /// Non-null while a broadcast is scheduled or currently draining.
  Timer? _broadcastTimer;

  bool get _pendingBroadcast => _broadcastTimer != null;

  void _cancelBroadcast() {
    _broadcastTimer?.cancel();
    _broadcastTimer = null;
  }

  void _scheduleBroadcast() {
    if (!_pendingBroadcast) {
      // The broadcast is run async so that multiple broadcast events can be batched
      // together into one update across all changes that occur in the current task of the event loop.
      _broadcastTimer = Timer(Duration.zero, _broadcast);
    }
  }

  void _broadcast() {
    for (final observer in _observers.toList()) {
      observer._onBroadcast();
    }

    eventStore.clear();
    _broadcastTimer = null;
  }

  void _broadcastDependents(
    StoreReference ref, {
    bool recursive = false,
  }) {
    final dependents = Loon._instance.dependencyManager
        .getDependents(ref, recursive: recursive);
    if (dependents != null) {
      for (final doc in dependents) {
        if (!eventStore.hasValue(doc.path)) {
          writeDocument(doc, BroadcastEvents.touched);
        }
      }
    }
  }

  void _deleteRef(StoreReference ref) {
    final StoreReference(:path) = ref;

    /// When a path is deleted, the event store is updated to remove all broadcast events
    /// scheduled for that path and its subtree and replaces the root of that broadcast store path
    /// with a single removed event.
    eventStore.delete(path);
    eventStore.write(path, BroadcastEvents.removed);

    // Deleting a path invalidates all cached values under that path in the observer value store.
    observerValueStore.delete(path);

    // Deleting a reference schedules all dependents under that path for broadcast.
    _broadcastDependents(ref, recursive: true);

    _scheduleBroadcast();
  }

  void writeDocument(Document doc, BroadcastEvents event) {
    final path = doc.path;

    // All cached observer values for the document and its collection are invalidated whenever
    // the document is written or touched.
    observerValueStore.delete(doc.path, recursive: false);
    observerValueStore.delete(doc.parent, recursive: false);

    final pendingEvent = eventStore.get(path);
    // Ignore writing a duplicate event or overwriting a pending mutative event type with a touched event.
    if (pendingEvent == null ||
        (event != pendingEvent && event != BroadcastEvents.touched)) {
      eventStore.write(path, event);
    }

    _broadcastDependents(doc);
    _scheduleBroadcast();
  }

  void deleteCollection(Collection collection) {
    _deleteRef(collection);
  }

  void deleteDocument(Document doc) {
    _deleteRef(doc);

    // All cached observer values for the document's collection are also invalidated after
    // the document is deleted.
    observerValueStore.delete(doc.parent, recursive: false);
  }

  void clear({bool broadcast = true}) {
    _cancelBroadcast();
    eventStore.clear();
    observerValueStore.clear();

    if (broadcast) {
      for (final observer in _observers) {
        eventStore.write(observer.path, BroadcastEvents.removed);
      }

      _scheduleBroadcast();
    }
  }

  void addObserver<T, S>(BroadcastObserver<T, S> observer, T initialValue) {
    _observers.add(observer);

    observerValueStore.write(observer._observerId, initialValue);
  }

  void removeObserver(BroadcastObserver observer) {
    _observers.remove(observer);

    observerValueStore.delete(observer._observerId);
  }

  void unsubscribe() {
    _cancelBroadcast();
    eventStore.clear();
    for (final observer in _observers.toList()) {
      observer.dispose();
    }
    _observers.clear();
    observerValueStore.clear();
  }

  Map inspect() {
    return {
      "events": eventStore.inspect(),
      "observerValues": observerValueStore.inspect(),
    };
  }
}
