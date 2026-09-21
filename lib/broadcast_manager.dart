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
    if (dependents == null || dependents.isEmpty) return;
    _queueDependentEvents(dependents);
  }

  void _queueDependentEvents(Set<Document> dependents) {
    final manager = Loon._instance.dependencyManager;

    // This synchronous walk only adds events and reads the reverse index. Keep
    // at most one collection map from each store, only until the walk returns.
    String? eventParent;
    Map<String, BroadcastEvents>? events;
    String? reverseParent;
    Map<String, Set<Document>>? reverse;

    void visit(Set<Document> dependents) {
      for (final doc in dependents) {
        // Unusual constructor inputs can split differently from parent/id.
        final useBucket = doc.id.isNotEmpty &&
            !doc.id.contains('__') &&
            !doc.parent.endsWith('_');
        if (useBucket && eventParent != doc.parent) {
          eventParent = doc.parent;
          events = eventStore.getChildValues(doc.parent);
        }
        final pending =
            useBucket ? (events?[doc.id]) : eventStore.get(doc.path);
        if (pending != null) continue;

        observerValueStore.delete(doc.path, recursive: false);
        observerValueStore.delete(doc.parent, recursive: false);
        if (useBucket && events != null) {
          events![doc.id] = BroadcastEvents.touched;
        } else {
          eventStore.write(doc.path, BroadcastEvents.touched);
          if (useBucket) {
            events = eventStore.getChildValues(doc.parent);
          } else {
            // This write may have created a bucket previously cached as absent.
            eventParent = null;
          }
        }

        Set<Document>? next;
        if (useBucket) {
          if (reverseParent != doc.parent) {
            reverseParent = doc.parent;
            reverse = manager._dependents.getChildValues(doc.parent);
          }
          next = reverse?[doc.id];
        } else {
          next = manager.getDependents(doc);
        }
        if (next != null) visit(next);
      }
    }

    visit(dependents);
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

    // All cached observer values for the document and its collection are invalidated whenever
    // the document is written or touched.
    observerValueStore.delete(path, recursive: false);
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
