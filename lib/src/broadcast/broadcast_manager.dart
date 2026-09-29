part of '../loon.dart';

enum BroadcastEvents {
  /// The document has been modified.
  modified,

  /// The document has been added.
  added,

  /// The document has been removed.
  removed,

  /// The document has been touched: its observers emit it again and the queries on its collection
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

  static final _dependencyManager = Loon._instance.dependencyManager;

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

  /// Broadcast all dependents of the given reference, marking them as touched.
  void _broadcastDependents(
    StoreReference ref, {
    bool recursive = false,
  }) {
    final dependents =
        _dependencyManager.getDependents(ref, recursive: recursive);
    if (dependents == null) {
      return;
    }

    final Set<String> collectionPaths = {};
    final Set<StoreReference> visited = {ref};

    void broadcastDep(Document doc) {
      collectionPaths.add(doc.parent);
      eventStore.putIfAbsent(doc.path, BroadcastEvents.touched);

      final deps = _dependencyManager.getDependents(doc);
      if (deps == null || !visited.add(doc)) {
        return;
      }

      for (final dep in deps) {
        broadcastDep(dep);
      }
    }

    for (final dep in dependents) {
      broadcastDep(dep);
    }

    // The collections of the touched documents have their cached observer values invalidated.
    // This is only done once per collection, reducing fanout of observer value updates when many documents
    // in a collection have been touched.
    for (final path in collectionPaths) {
      observerValueStore.delete(path, recursive: false);
    }
  }

  void _deleteRef(StoreReference ref) {
    final StoreReference(:path) = ref;

    // Replace all pending events for the deleted path and its subtree with a
    // single removed event at the deleted path.
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

    // All cached observer values for the document's collection are invalidated whenever
    // the document is written or rebroadcast.
    observerValueStore.delete(path, recursive: false);
    observerValueStore.delete(doc.parent, recursive: false);

    // A touched event doesn't replace a pending event.
    if (event == BroadcastEvents.touched) {
      eventStore.putIfAbsent(path, event);
    } else {
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
    observerValueStore.clear();

    for (final observer in _observers.toList()) {
      observer.dispose();
    }
    _observers.clear();
  }

  Map inspect() {
    return {
      "events": eventStore.inspect(),
      "observerValues": observerValueStore.inspect(),
    };
  }
}
