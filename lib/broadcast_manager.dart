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

  /// The set of broadcast observers that should be notified on broadcast.
  final Set<BroadcastObserver> _observers = {};

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
      try {
        observer._onBroadcast();
      } catch (error, stackTrace) {
        // An observer can throw while processing a broadcast, for example if a query's filter throws.
        // The error is reported rather than thrown so that the remaining observers still process the
        // broadcast, since its events are cleared once it completes.
        FlutterError.reportError(
          FlutterErrorDetails(
            exception: error,
            stack: stackTrace,
            library: 'loon',
            context: ErrorDescription(
              'while broadcasting to an observer of ${observer.path}',
            ),
          ),
        );
      }
    }

    eventStore.clear();
    _broadcastTimer = null;
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

  /// Schedules the dependents of the document or collection at the given path, and of every document
  /// under it, for broadcast. Used when a path is deleted, since the documents under it are removed
  /// together and each of their dependents needs to be re-evaluated.
  void _broadcastPathDependents(String path) {
    final dependents = Loon._instance.dependencyManager.getPathDependents(path);
    for (final doc in dependents) {
      if (!eventStore.hasValue(doc.path)) {
        writeDocument(doc, BroadcastEvents.touched);
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

    // Deleting a path also schedules all dependents under that path for broadcast.
    _broadcastPathDependents(path);

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
    _deletePath(collection.path);
  }

  void deleteDocument(Document doc) {
    _deletePath(doc.path);

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
