library loon;

import 'dart:async';

export 'widgets/query_stream_builder.dart';
export 'widgets/document_stream_builder.dart';

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
part 'dependency_store.dart';

typedef CollectionStore = Map<String, Map<String, DocumentSnapshot>>;
typedef BroadcastCollectionStore = Map<String, Map<String, BroadcastDocument>>;

class Loon {
  Persistor? persistor;

  static final Loon _instance = Loon._();

  Loon._();

  /// Document data is stored in a dynamic collection mixing snapshots of both serialized and parsed data. Documents are initially hydrated in their serialized
  /// representation, since de-serializers cannot be known ahead of time. They are then cached in their parsed representation when they are first accessed
  /// using a serializer. Caching the parsed document snapshots is necessary in order to improve the performance of repeatedly reading document data.
  final CollectionStore _collectionStore = {};

  /// The collection store of documents that are pending a scheduled broadcast.
  final BroadcastCollectionStore _broadcastCollectionStore = {};

  /// The list of observers, either document or query observables, that should be notified on broadcast.
  final Set<BroadcastObserver> _broadcastObservers = {};

  final _dependencyStore = _DependencyStore();

  bool _hasPendingBroadcast = false;

  static bool _isHydrating = false;

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
  DocumentSnapshot<T>? _getSnapshot<T>(Document<T> doc) {
    final snap = _collectionStore[doc.collection]?[doc.id];

    if (snap == null) {
      return null;
    }

    if (snap is DocumentSnapshot<Json> && T != Json && T != dynamic) {
      _validateTypeSerialization<T>(
        fromJson: doc.fromJson,
        toJson: doc.toJson,
      );

      // Upon first read of serialized data using a serializer, the parsed representation
      // of the document is cached for efficient repeat access. It does not need to be rebroadcast.
      return _writeSnapshot<T>(doc, doc.fromJson!(snap.data), broadcast: false);
    }

    return snap as DocumentSnapshot<T>;
  }

  /// Returns whether a collection name exists in the collection data store.
  bool _hasCollection(String name) {
    return _collectionStore.containsKey(name);
  }

  bool get _isGlobalPersistenceEnabled {
    return _instance.persistor?.persistorSettings.persistenceEnabled ?? false;
  }

  /// Clears the given collection from the store.
  void _clearCollection(
    Collection collection, {
    bool broadcast = true,
  }) {
    final collectionName = collection.name;

    // Immediately clear any documents in the collection scheduled for broadcast, as whatever event happened prior to the clear
    // in the collection are now irrelevant.
    _broadcastCollectionStore[collectionName]?.clear();

    final snaps = _getSnapshots(collectionName);
    for (final snap in snaps) {
      snap.doc.delete(broadcast: broadcast);
    }

    if (collection.isPersistenceEnabled()) {
      persistor!._clear(collection.name);
    }
  }

  /// Clears all data from the store.
  void _clearAll({
    bool broadcast = true,
  }) {
    // Immediately clear any documents scheduled for broadcast, as whatever events happened prior to the clear are now irrelevant.
    _broadcastCollectionStore.clear();
    // Immediately clear all dependencies of documents, since all documents are being removed and will be broadcast if indicated.
    _dependencyStore.clearAll();

    // If it should broadcast, then we need to go through every document that is being
    // cleared and schedule it for broadcast.
    if (broadcast) {
      for (final collectionName in _collectionStore.keys) {
        final snaps = _getSnapshots(collectionName);

        for (final snap in snaps) {
          _writeBroadcastDocument(snap.doc, BroadcastEventTypes.removed);
        }
      }
    }

    _collectionStore.clear();

    if (persistor != null) {
      persistor!._clearAll();
    }
  }

  /// Returns whether a document exists in the collection data store.
  bool _hasDocument(Document doc) {
    return _collectionStore[doc.collection]?.containsKey(doc.id) ?? false;
  }

  void _replaceCollection<T>(
    String collection, {
    required List<DocumentSnapshot<T>> snaps,
    FromJson<T>? fromJson,
    ToJson<T>? toJson,
    PersistorSettings<T>? persistorSettings,
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
        existingSnap.doc.update(updatedSnap.data);
      } else {
        existingSnap.doc.delete();
      }
    }

    for (final newSnap in snapsById.values) {
      newSnap.doc.create(newSnap.data);
    }
  }

  /// Returns a list of data snapshots for the given collection.
  List<DocumentSnapshot<T>> _getSnapshots<T>(
    String collection, {
    FromJson<T>? fromJson,
    ToJson<T>? toJson,
    PersistorSettings<T>? persistorSettings,
  }) {
    if (!_hasCollection(collection)) {
      return [];
    }

    return _collectionStore[collection]!.values.map((snap) {
      if (snap is DocumentSnapshot<Json> && T != Json && T != dynamic) {
        _validateTypeSerialization<T>(
          fromJson: fromJson,
          toJson: toJson,
        );

        // Upon first read of serialized data using a serializer, the parsed representation
        // of the document is cached for efficient repeat access.
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
        );
      }

      return snap as DocumentSnapshot<T>;
    }).toList();
  }

  BroadcastDocument<T>? _getBroadcastDocument<T>(
    String collection,
    String id, {
    FromJson<T>? fromJson,
    ToJson<T>? toJson,
    PersistorSettings<T>? persistorSettings,
  }) {
    if (!_broadcastCollectionStore.containsKey(collection)) {
      return null;
    }

    final doc = _broadcastCollectionStore[collection]![id];

    if (doc == null) {
      return null;
    }

    if (doc is BroadcastDocument<T>) {
      return doc;
    } else {
      // If the broadcast document was created through the hydration process, then its broadcast document is likely Json assuming
      // it hasn't modified since hydration already. In this case, it can now lazily be converted to the provided collection type.
      return BroadcastDocument<T>(
        Document<T>(
          collection: collection,
          id: doc.id,
          fromJson: fromJson,
          toJson: toJson,
          persistorSettings: persistorSettings,
        ),
        doc.type,
      );
    }
  }

  /// Returns the list of documents in the given collection that have been added, removed or modified since the last broadcast.
  List<BroadcastDocument<T>> _getBroadcastDocuments<T>(
    String collection, {
    FromJson<T>? fromJson,
    ToJson<T>? toJson,
    PersistorSettings<T>? persistorSettings,
  }) {
    if (!_broadcastCollectionStore.containsKey(collection)) {
      return [];
    }

    return _broadcastCollectionStore[collection]!.values.map((doc) {
      return _getBroadcastDocument<T>(
        collection,
        doc.id,
        fromJson: fromJson,
        toJson: toJson,
        persistorSettings: persistorSettings,
      )!;
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
    return _instance._broadcastCollectionStore.containsKey(query.name);
  }

  bool _isDocumentPendingBroadcast<T>(Document<T> doc) {
    return _instance._broadcastCollectionStore[doc.collection]
            ?.containsKey(doc.id) ??
        false;
  }

  void _broadcast() {
    for (final observer in _broadcastObservers) {
      observer._onBroadcast();
    }

    for (final broadcastCollection in _broadcastCollectionStore.values) {
      broadcastCollection.clear();
    }
  }

  DocumentSnapshot<T> _writeSnapshot<T>(
    Document<T> doc,
    T data, {
    bool broadcast = true,
  }) {
    if (data is! Json && doc.isPersistenceEnabled()) {
      _validateDataSerialization<T>(
        fromJson: doc.fromJson,
        toJson: doc.toJson,
        data: data,
      );
    }

    final collection = doc.collection;

    if (!_collectionStore.containsKey(collection)) {
      _collectionStore[collection] = {};
    }

    final BroadcastEventTypes eventType;
    if (_isHydrating) {
      eventType = BroadcastEventTypes.hydrated;
    } else if (doc.exists()) {
      eventType = BroadcastEventTypes.modified;
    } else {
      eventType = BroadcastEventTypes.added;
    }

    final snap =
        _collectionStore[doc.collection]![doc.id] = DocumentSnapshot<T>(
      doc: doc,
      data: data,
    );

    _dependencyStore.rebuildDependencies(snap);

    if (broadcast) {
      _writeBroadcastDocument<T>(doc, eventType);
    }

    if (doc.isPersistenceEnabled()) {
      persistor!._persistDoc(doc);
    }

    return snap;
  }

  DocumentSnapshot<T> _addDocument<T>(
    Document<T> doc,
    T data, {
    bool broadcast = true,
  }) {
    if (_hasDocument(doc)) {
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
      throw Exception('Missing document ${doc.path}');
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

    _collectionStore[doc.collection]!.remove(doc.id);
    _dependencyStore.clearDependencies(doc);

    if (broadcast) {
      _writeBroadcastDocument<T>(doc, BroadcastEventTypes.removed);
    }

    if (doc.isPersistenceEnabled()) {
      persistor!._persistDoc(doc);
    }
  }

  void _writeBroadcastDocument<T>(
    Document<T> doc,
    BroadcastEventTypes eventType,
  ) {
    final pendingBroadcastDoc =
        _broadcastCollectionStore[doc.collection]?[doc.id];

    // Ignore writing a duplicate broadcast event type or overwriting a pending mutative event type with a touched event.
    if (pendingBroadcastDoc != null &&
        (pendingBroadcastDoc.type == eventType ||
            eventType == BroadcastEventTypes.touched)) {
      return;
    }

    if (!_broadcastCollectionStore.containsKey(doc.collection)) {
      _broadcastCollectionStore[doc.collection] = {};
    }

    final broadcastDoc = _broadcastCollectionStore[doc.collection]![doc.id] =
        doc.toBroadcast(eventType);

    _rebroadcastDependents(broadcastDoc);

    _scheduleBroadcast();
  }

  /// Schedules all dependents of the given document for rebroadcast. This occurs
  /// for any type of broadcast (added, modified, removed or touched).
  void _rebroadcastDependents(BroadcastDocument doc) {
    final dependents = _dependencyStore.getDependents(doc);

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
      return;
    }
    try {
      _isHydrating = true;
      final data = await _instance.persistor!._hydrate();

      for (final collectionDataStoreEntry in data.entries) {
        final collection = collectionDataStoreEntry.key;
        final documentDataStore = collectionDataStoreEntry.value;

        for (final documentDataEntry in documentDataStore.entries) {
          _instance._writeSnapshot<Json>(
            Document<Json>(collection: collection, id: documentDataEntry.key),
            documentDataEntry.value,
          );
        }
      }
    } catch (e) {
      // ignore: avoid_print
      print('Loon: Error hydrating');
    } finally {
      _isHydrating = false;
    }
  }

  static Collection<T> collection<T>(
    String collection, {
    FromJson<T>? fromJson,
    ToJson<T>? toJson,
    PersistorSettings<T>? persistorSettings,
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
    PersistorSettings<T>? persistorSettings,
  }) {
    return collection<T>(
      '__ROOT__',
      fromJson: fromJson,
      toJson: toJson,
      persistorSettings: persistorSettings,
    ).doc(id);
  }

  static void clearAll({
    bool broadcast = true,
  }) {
    Loon._instance._clearAll(broadcast: broadcast);
  }

  /// Enqueues a document to be rebroadcasted, updating all listeners that are subscribed to that document.
  static void rebroadcast(Document doc) {
    _instance._writeBroadcastDocument(
      doc,
      BroadcastEventTypes.touched,
    );
  }

  /// Returns a Map of all of the data and metadata of the store for debugging and inspection purposes.
  static Json extract() {
    return {
      "collectionStore": _instance._collectionStore,
      "broadcastCollectionStore": _instance._broadcastCollectionStore,
      "dependencyStore": {
        "dependencies": _instance._dependencyStore._dependenciesStore,
        "dependents": _instance._dependencyStore._dependentsStore,
      },
    };
  }
}
