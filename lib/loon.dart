library loon;

import 'dart:async';

import 'package:flutter/foundation.dart';

export 'widgets/query_stream_builder.dart';
export 'widgets/document_stream_builder.dart';
export 'persistor/file_persistor/file_persistor.dart';

part 'store_node.dart';
part 'broadcast_observer.dart';
part 'query.dart';
part 'observable_query.dart';
part 'collection.dart';
part 'document.dart';
part 'observable_document.dart';
part 'types.dart';
part 'document_snapshot.dart';
part 'persistor/persistor.dart';
part 'document_change_snapshot.dart';
part 'document_dependency_store.dart';
part 'utils.dart';

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

/// Set of broadcast observers by collection.
typedef BroadcastObserverStore = Set<BroadcastObserver>;

class Loon {
  Persistor? persistor;

  static final Loon _instance = Loon._();

  Loon._();

  /// The store of document snapshots indexed by their document path.
  final StoreNode<DocumentSnapshot> _store = StoreNode();

  /// The store of broadcast types for documents scheduled to be broadcast, indexed by their collection.
  final StoreNode<EventTypes> _broadcastStore = StoreNode();

  /// The store of broadcast observers that should be notified on broadcast.
  final BroadcastObserverStore _broadcastObservers = {};

  final _documentDependencyStore = _DocumentDependencyStore();

  bool _hasPendingBroadcast = false;

  bool enableLogging = false;

  bool get _isGlobalPersistenceEnabled {
    return _instance.persistor?.settings.persistenceEnabled ?? false;
  }

  void _deleteCollection(
    Collection collection, {
    bool broadcast = true,
    bool persist = true,
  }) {
    final path = collection.path;
    _store.delete(path);
    _broadcastStore.delete(path);

    _documentDependencyStore.clear(path);
    persistor?._clear(path);

    // Clear all observers watching documents of the collection ands its subcollections.
    // Given the sparse number of active observers relative to documents, this should be
    // relatively performant.
    for (final observer in _broadcastObservers) {
      if (observer.path.startsWith(path)) {
        observer._onClear();
      }
    }
  }

  /// Clears all data from the store.
  Future<void> _clearAll({
    bool broadcast = true,
  }) async {
    // Clear the store.
    _store.clear();
    // Clear any documents scheduled for broadcast, as whatever events happened prior to the clear are now irrelevant.
    _broadcastStore.clear();
    // Clear all dependencies of documents.
    _documentDependencyStore.clearAll();

    if (broadcast) {
      for (final observer in _broadcastObservers) {
        observer._onClear();
      }
    }

    return persistor?._clearAll();
  }

  void _addBroadcastObserver(BroadcastObserver observer) {
    _broadcastObservers.add(observer);
  }

  void _removeBroadcastObserver(BroadcastObserver observer) {
    _broadcastObservers.remove(observer);
  }

  bool _isQueryPendingBroadcast<T>(Query<T> query) {
    return _instance._broadcastStore.contains(query.collection.path);
  }

  bool _isDocumentPendingBroadcast<T>(Document<T> doc) {
    return _instance._broadcastStore.contains(doc.path);
  }

  void _broadcast() {
    for (final observer in _broadcastObservers) {
      observer._onBroadcast();
    }
    _broadcastStore.clear();
  }

  DocumentSnapshot<T>? _getDoc<T>(Document<T> doc) {
    return _store.get(doc.path) as DocumentSnapshot<T>?;
  }

  DocumentSnapshot<T> _writeDoc<T>(
    Document<T> doc,
    T data, {
    required EventTypes event,
    bool broadcast = true,
    bool persist = true,
  }) {
    _validateDataSerialization(
      data: data,
      fromJson: doc.fromJson,
      toJson: doc.toJson,
    );

    final snap = DocumentSnapshot(doc: doc, data: data);
    _store.write(doc.path, snap);

    if (broadcast) {
      _broadcastDoc(doc, event);
    }

    _documentDependencyStore.rebuildDependencies(doc.get()!);

    if (persist && doc.isPersistenceEnabled()) {
      persistor!._persistDoc(doc);
    }

    return snap;
  }

  void _deleteDoc<T>(
    Document<T> doc, {
    bool broadcast = true,
  }) {
    if (!doc.exists()) {
      return;
    }

    _store.delete(doc.path);
    _documentDependencyStore.clearDependencies(doc);

    if (broadcast) {
      _broadcastDoc(doc, EventTypes.removed);
    }

    if (doc.isPersistenceEnabled()) {
      persistor!._persistDoc(doc);
    }
  }

  EventTypes? _getBroadcastDoc<T>(Document<T> doc) {
    return _broadcastStore.get(doc.path);
  }

  Map<String, EventTypes>? _getBroadcastCollection<T>(Collection collection) {
    return _broadcastStore.getAll(collection.path);
  }

  void _broadcastDoc<T>(
    Document<T> doc,
    EventTypes event,
  ) {
    final pendingEvent = _broadcastStore.get(doc.path);

    // Ignore writing a duplicate event type or overwriting a pending mutative event type with a touched event.
    if (pendingEvent != null &&
        (pendingEvent == event || pendingEvent == EventTypes.touched)) {
      return;
    }

    _broadcastStore.write(doc.path, event);

    _rebroadcastDependents(doc);
    _scheduleBroadcast();
  }

  /// Schedules all dependents of the given document for rebroadcast. This occurs
  /// for any type of broadcast (added, modified, removed or touched).
  void _rebroadcastDependents(Document doc) {
    final dependents = _documentDependencyStore.getDependents(doc);

    if (dependents != null) {
      for (final dependent in dependents) {
        rebroadcast(dependent);
      }
    }
  }

  _scheduleBroadcast() {
    if (!_hasPendingBroadcast) {
      _hasPendingBroadcast = true;

      // Schedule a broadcast event to be run on the microtask queue.
      scheduleMicrotask(() {
        _broadcast();
        _hasPendingBroadcast = false;
      });
    }
  }

  List<DocumentSnapshot<T>> getCollection<T>(Collection<T> collection) {
    return (_store.getAll(collection.path)?.values.toList() ?? [])
        as List<DocumentSnapshot<T>>;
  }

  static void configure({
    Persistor? persistor,
    bool enableLogging = false,
  }) {
    _instance.enableLogging = enableLogging;
    _instance.persistor = persistor;
  }

  static Future<void> hydrate() async {
    if (_instance.persistor == null) {
      printDebug('Hydration skipped - no persistor specified');
      return;
    }
    try {
      final data = await _instance.persistor!._hydrate();

      for (final collectionDataStore in data.entries) {
        final collectionName = collectionDataStore.key;
        final documentDataStore = collectionDataStore.value;

        for (final documentDataEntry in documentDataStore.entries) {
          _instance._writeDoc(
            Loon.collection<Json>(collectionName).doc(documentDataEntry.key),
            documentDataEntry.value,
            event: EventTypes.hydrated,
            persist: false,
          );
        }
      }
    } catch (e) {
      // ignore: avoid_print
      printDebug('Error hydrating');
      rethrow;
    }
  }

  static Collection<T> collection<T>(
    String name, {
    FromJson<T>? fromJson,
    ToJson<T>? toJson,
    PersistorSettings? persistorSettings,
    DependenciesBuilder<T>? dependenciesBuilder,
  }) {
    return Document.root.subcollection<T>(
      name,
      fromJson: fromJson,
      toJson: toJson,
      persistorSettings: persistorSettings,
      dependenciesBuilder: dependenciesBuilder,
    );
  }

  static Future<void> clearAll({
    bool broadcast = true,
  }) {
    return Loon._instance._clearAll(broadcast: broadcast);
  }

  /// Schedules a document to be rebroadcasted, updating all listeners that are subscribed to that document.
  static void rebroadcast(Document doc) {
    _instance._broadcastDoc(doc, EventTypes.touched);
  }

  /// Returns a Map of all of the data and metadata of the store for debugging and inspection purposes.
  static Json inspect() {
    return {
      "store": _instance._store.inspect(),
      "broadcastStore": _instance._broadcastStore.inspect(),
      "dependencyStore": {
        "dependencies": _instance._documentDependencyStore._dependenciesStore,
        "dependents": _instance._documentDependencyStore._dependentsStore,
      },
    };
  }

  static bool get isLoggingEnabled {
    return _instance.enableLogging;
  }
}
