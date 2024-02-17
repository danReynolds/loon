library loon;

import 'dart:async';

import 'package:loon/utils.dart';

export 'widgets/query_stream_builder.dart';
export 'widgets/document_stream_builder.dart';
export 'persistor/file_persistor/file_persistor.dart';

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

typedef DocumentStore = Map<String, Map<String, DocumentSnapshot>>;
typedef DocumentBroadcastStore = Map<String, Map<String, BroadcastEventTypes>>;

class Loon {
  Persistor? persistor;

  static final Loon _instance = Loon._();

  Loon._();

  /// The store of document snapshots indexed by their collections.
  final DocumentStore _documentStore = {};

  /// The store of broadcast types for documents scheduled to be broadcast, indexed by their collection.
  final DocumentBroadcastStore _documentBroadcastStore = {};

  /// The list of observers, either document or query observables, that should be notified on broadcast.
  final Set<BroadcastObserver> _broadcastObservers = {};

  final _documentDependencyStore = _DocumentDependencyStore();

  bool _hasPendingBroadcast = false;

  /// Validates that data is either already in a serializable format or comes with a serializer.
  static void _validateDataSerialization<T>({
    required FromJson<T>? fromJson,
    required ToJson<T>? toJson,
    required T? data,
  }) {
    if (data is! Json? && (fromJson == null || toJson == null)) {
      throw Exception('Missing fromJson/toJson serializer');
    }
  }

  /// Validates that a type is either already serialized or comes with a serializer.
  static void _validateTypeSerialization<T>({
    required FromJson<T>? fromJson,
    required ToJson<T>? toJson,
  }) {
    if (T != Json && T != dynamic && (fromJson == null && toJson == null)) {
      throw Exception('Missing fromJson/toJson serializer');
    }
  }

  /// Returns a data snapshot for the given document.
  DocumentSnapshot<T>? _getSnapshot<T>({
    required String id,
    required String collection,
    FromJson<T>? fromJson,
    ToJson<T>? toJson,
    PersistorSettings? persistorSettings,
  }) {
    final snap = _documentStore[collection]?[id];

    if (snap == null) {
      return null;
    }

    if (snap is DocumentSnapshot<Json> && T != Json && T != dynamic) {
      _validateTypeSerialization<T>(
        fromJson: fromJson,
        toJson: toJson,
      );

      // When a document is read, if it is still in JSON format from hydration and is now being accessed
      // with a serializer, then it is de-serialized at time of access.
      return _writeSnapshot<T>(
        Document<T>(
          id: id,
          collection: collection,
          fromJson: fromJson,
          toJson: toJson,
          persistorSettings: persistorSettings,
        ),
        fromJson!(snap.data),
        broadcast: false,
        persist: false,
      );
    }

    return snap as DocumentSnapshot<T>;
  }

  bool get _isGlobalPersistenceEnabled {
    return _instance.persistor?.persistorSettings.persistenceEnabled ?? false;
  }

  void _deleteCollection(
    String collection, {
    bool broadcast = true,
    bool persist = true,
  }) {
    final collectionStore = _documentStore[collection];
    if (collectionStore == null) {
      return;
    }

    // Immediately clear any documents in the collection scheduled for broadcast, as all broadcasts that had previously
    // been scheduled for documents in the collection are now invalidated.
    _documentBroadcastStore[collection]?.clear();

    if (broadcast) {
      for (final snap in collectionStore.values) {
        _writeDocumentBroadcast(snap.doc, BroadcastEventTypes.removed);
      }
    }

    _documentStore.remove(collection);
    _documentDependencyStore.clear(collection);
    persistor?._clear(collection);

    // Delete all subcollections of this collection.
    for (final otherCollection in _documentStore.keys.toList()) {
      if (collection != otherCollection &&
          otherCollection.startsWith('${collection}__')) {
        _deleteCollection(
          otherCollection,
          broadcast: broadcast,
          // Subcollections of the deleted collection do not need to be persisted
          // as the default behavior of clearing a collection at the persistence layer
          // is to clear all subcollections as well.
          persist: false,
        );
      }
    }
  }

  /// Clears all data from the store.
  Future<void> _clearAll({
    bool broadcast = false,
  }) async {
    // Immediately clear any documents scheduled for broadcast, as whatever events happened prior to the clear are now irrelevant.
    _documentBroadcastStore.clear();
    // Immediately clear all dependencies of documents, since all documents are being removed and will be broadcast if indicated.
    _documentDependencyStore.clearAll();

    // If it should broadcast, then we need to go through every document that is being
    // cleared and schedule it for broadcast.
    if (broadcast) {
      for (final collectionName in _documentStore.keys) {
        final collectionStore = _documentStore[collectionName];

        if (collectionStore == null) {
          continue;
        }

        for (final snap in collectionStore.values) {
          _writeDocumentBroadcast(snap.doc, BroadcastEventTypes.removed);
        }
      }
    }

    _documentStore.clear();
    return persistor?._clearAll();
  }

  /// Returns whether a document exists in the collection data store.
  bool _hasDocument(Document doc) {
    return _documentStore[doc.collection]?.containsKey(doc.id) ?? false;
  }

  bool _hasCollection(String collection) {
    return _documentStore.containsKey(collection);
  }

  void _replaceCollection<T>(
    String collection, {
    required List<DocumentSnapshot<T>> snaps,
    FromJson<T>? fromJson,
    ToJson<T>? toJson,
    PersistorSettings? persistorSettings,
    bool broadcast = true,
  }) {
    final snapsById =
        snaps.fold<Map<String, DocumentSnapshot<T>>>({}, (acc, snap) {
      acc[snap.id] = snap;
      return acc;
    });

    final existingSnaps = _getSnapshots<T>(
      collection,
      fromJson: fromJson,
      toJson: toJson,
      persistorSettings: persistorSettings,
    );

    for (final existingSnap in existingSnaps) {
      final docId = existingSnap.id;
      final updatedSnap = snapsById[docId];

      if (updatedSnap != null) {
        existingSnap.doc.update(updatedSnap.data, broadcast: broadcast);
      } else {
        existingSnap.doc.delete(broadcast: broadcast);
      }
    }

    for (final newSnap in snapsById.values) {
      if (!newSnap.doc.exists()) {
        newSnap.doc.create(newSnap.data, broadcast: broadcast);
      }
    }
  }

  /// Returns a list of data snapshots for the given collection.
  List<DocumentSnapshot<T>> _getSnapshots<T>(
    String collection, {
    FromJson<T>? fromJson,
    ToJson<T>? toJson,
    PersistorSettings? persistorSettings,
  }) {
    if (!_hasCollection(collection)) {
      return [];
    }

    return _documentStore[collection]!.values.map((snap) {
      if (snap is DocumentSnapshot<Json> && T != Json && T != dynamic) {
        _validateTypeSerialization<T>(
          fromJson: fromJson,
          toJson: toJson,
        );

        // When a document is read, if it is still in JSON format from hydration and is now being accessed
        // with a serializer, then it is de-serialized at time of access.
        return _writeSnapshot<T>(
          Document<T>(
            id: snap.doc.id,
            collection: collection,
            fromJson: fromJson,
            toJson: toJson,
            persistorSettings: persistorSettings,
          ),
          fromJson!(snap.data),
          broadcast: false,
          persist: false,
        );
      }

      return snap as DocumentSnapshot<T>;
    }).toList();
  }

  void _addBroadcastObserver(BroadcastObserver observer) {
    _broadcastObservers.add(observer);
  }

  void _removeBroadcastObserver(BroadcastObserver observer) {
    _broadcastObservers.remove(observer);
  }

  void _scheduleBroadcast() {
    if (!_hasPendingBroadcast) {
      _hasPendingBroadcast = true;

      // Schedule a broadcast event to be run on the microtask queue.
      scheduleMicrotask(() {
        _broadcast();
        _hasPendingBroadcast = false;
      });
    }
  }

  bool _isQueryPendingBroadcast<T>(Query<T> query) {
    return _instance._documentBroadcastStore.containsKey(query.name);
  }

  bool _isDocumentPendingBroadcast<T>(Document<T> doc) {
    return _instance._documentBroadcastStore[doc.collection]
            ?.containsKey(doc.id) ??
        false;
  }

  void _broadcast() {
    for (final observer in _broadcastObservers) {
      observer._onBroadcast();
    }
    _documentBroadcastStore.clear();
  }

  DocumentSnapshot<T> _writeSnapshot<T>(
    Document<T> doc,
    T data, {
    bool broadcast = true,
    bool persist = true,
    bool hydrating = false,
  }) {
    if (data is! Json && doc.isPersistenceEnabled()) {
      _validateDataSerialization<T>(
        fromJson: doc.fromJson,
        toJson: doc.toJson,
        data: data,
      );
    }

    final collection = doc.collection;

    if (!_documentStore.containsKey(collection)) {
      _documentStore[collection] = {};
    }

    final BroadcastEventTypes broadcastType;
    if (hydrating) {
      broadcastType = BroadcastEventTypes.hydrated;
    } else if (doc.exists()) {
      broadcastType = BroadcastEventTypes.modified;
    } else {
      broadcastType = BroadcastEventTypes.added;
    }

    final snap = _documentStore[doc.collection]![doc.id] = DocumentSnapshot<T>(
      doc: doc,
      data: data,
    );

    _documentDependencyStore.rebuildDependencies(snap);

    if (broadcast) {
      _writeDocumentBroadcast(doc, broadcastType);
    }

    if (persist && doc.isPersistenceEnabled()) {
      persistor!._persistDoc(doc);
    }

    return snap;
  }

  DocumentSnapshot<T> _addDocument<T>(
    Document<T> doc,
    T data, {
    bool broadcast = true,
  }) {
    if (doc.exists()) {
      throw Exception('Cannot add duplicate document');
    }

    return _writeSnapshot<T>(doc, data, broadcast: broadcast);
  }

  DocumentSnapshot<T> _updateDocument<T>(
    Document<T> doc,
    T data, {
    bool broadcast = true,
  }) {
    if (!doc.exists()) {
      throw Exception('Missing document ${doc.key}');
    }

    return _writeSnapshot<T>(
      doc,
      data,
      // As an optimization, broadcasting is skipped when updating a document if the document
      // data is unchanged.
      broadcast: broadcast && doc.get()?.data != data,
    );
  }

  DocumentSnapshot<T> _modifyDocument<T>(
    Document<T> doc,
    ModifyFn<T> modifyFn, {
    bool broadcast = true,
  }) {
    return _updateDocument<T>(doc, modifyFn(doc.get()), broadcast: broadcast);
  }

  void _deleteDocument<T>(
    Document<T> doc, {
    bool broadcast = true,
  }) {
    if (!doc.exists()) {
      return;
    }

    _documentStore[doc.collection]!.remove(doc.id);
    _documentDependencyStore.clearDependencies(doc);

    if (broadcast) {
      _writeDocumentBroadcast<T>(doc, BroadcastEventTypes.removed);
    }

    if (doc.isPersistenceEnabled()) {
      persistor!._persistDoc(doc);
    }
  }

  void _writeDocumentBroadcast<T>(
    Document<T> doc,
    BroadcastEventTypes broadcastType,
  ) {
    final pendingBroadcastType =
        _documentBroadcastStore[doc.collection]?[doc.id];

    // Ignore writing a duplicate broadcast event type or overwriting a pending mutative event type with a touched event.
    if (pendingBroadcastType != null &&
        (pendingBroadcastType == broadcastType ||
            broadcastType == BroadcastEventTypes.touched)) {
      return;
    }

    _documentBroadcastStore[doc.collection] ??= {};
    _documentBroadcastStore[doc.collection]![doc.id] = broadcastType;

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

  static void configure({
    Persistor? persistor,
  }) {
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
        final collection = collectionDataStore.key;
        final documentDataStore = collectionDataStore.value;

        for (final documentDataEntry in documentDataStore.entries) {
          _instance._writeSnapshot<Json>(
            Document<Json>(id: documentDataEntry.key, collection: collection),
            documentDataEntry.value,
            persist: false,
            hydrating: true,
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
    String collection, {
    FromJson<T>? fromJson,
    ToJson<T>? toJson,
    PersistorSettings? persistorSettings,
    DependenciesBuilder<T>? dependenciesBuilder,
  }) {
    return Collection<T>(
      collection,
      fromJson: fromJson,
      toJson: toJson,
      persistorSettings: persistorSettings,
      dependenciesBuilder: dependenciesBuilder,
    );
  }

  static Document<T> doc<T>(
    String id, {
    FromJson<T>? fromJson,
    ToJson<T>? toJson,
    PersistorSettings? persistorSettings,
  }) {
    return collection<T>(
      '__ROOT__',
      fromJson: fromJson,
      toJson: toJson,
      persistorSettings: persistorSettings,
    ).doc(id);
  }

  static Future<void> clearAll({
    bool broadcast = false,
  }) {
    return Loon._instance._clearAll(broadcast: broadcast);
  }

  /// Enqueues a document to be rebroadcasted, updating all listeners that are subscribed to that document.
  static void rebroadcast(Document doc) {
    _instance._writeDocumentBroadcast(
      doc,
      BroadcastEventTypes.touched,
    );
  }

  /// Returns a Map of all of the data and metadata of the store for debugging and inspection purposes.
  static Json extract() {
    return {
      "collectionStore": _instance._documentStore,
      "documentBroadcastStore": _instance._documentBroadcastStore,
      "dependencyStore": {
        "dependencies": _instance._documentDependencyStore._dependenciesStore,
        "dependents": _instance._documentDependencyStore._dependentsStore,
      },
    };
  }
}
