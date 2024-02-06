library loon;

import 'dart:async';

export 'widgets/query_stream_builder.dart';
export 'widgets/document_stream_builder.dart';
export 'persistor/file_persistor.dart';
export 'persistor/encrypted_file_persistor.dart';

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

  /// The index of a document to the documents that depend on it. Whenever a document is updated, it schedules
  /// each of its dependents for a broadcast so that they can receive its updated value.
  final Map<Document, Set<Document>> _dependenciesStore = {};

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
    if (T != Json && T != dynamic && (fromJson == null || toJson == null)) {
      throw Exception('Missing fromJson/toJson serializer');
    }
  }

  /// Returns a data snapshot for the given document.
  DocumentSnapshot<T>? _getSnapshot<T>(Document<T> doc) {
    final snap = _collectionStore[doc.collection]?[doc.id];

    if (snap == null) {
      return null;
    }

    if (snap is DocumentSnapshot<T>) {
      return snap;
    }

    final fromJson = doc.fromJson;

    _validateTypeSerialization<T>(
      fromJson: doc.fromJson,
      toJson: doc.toJson,
    );

    // Upon first read of serialized data using a serializer, the parsed representation
    // of the document is cached for efficient repeat access. It does not need to be rebroadcast.
    return _writeSnapshot<T>(doc, fromJson!(snap.data), broadcast: false);
  }

  /// Returns whether a collection name exists in the collection data store.
  bool _hasCollection(String collection) {
    return _collectionStore.containsKey(collection);
  }

  bool get _isGlobalPersistenceEnabled {
    return _instance.persistor?.persistorSettings.persistenceEnabled ?? false;
  }

  bool _isDocumentPersistenceEnabled(Document doc) {
    return doc.persistorSettings?.persistenceEnabled ??
        _isGlobalPersistenceEnabled;
  }

  /// Clears the given collection name from the collection data store.
  Future<void> _clearCollection(String collection) async {
    if (_hasCollection(collection)) {
      _collectionStore.remove(collection);
      _scheduleBroadcast();

      if (persistor != null) {
        return persistor!.clear(collection);
      }
    }
  }

  /// Clears the entire collection data store.
  Future<void> _clearAll() async {
    if (_collectionStore.isEmpty) {
      return;
    }

    _collectionStore.clear();
    _scheduleBroadcast();

    if (persistor != null) {
      return persistor!.clearAll();
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
      snapsById.remove(docId);

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
      if (snap is DocumentSnapshot<T>) {
        return snap;
      }

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
    }).toList();
  }

  BroadcastDocument<T>? _getBroadcastDocument<T>(
    String collection,
    String id, {
    FromJson<T>? fromJson,
    ToJson<T>? toJson,
    PersistorSettings? persistorSettings,
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
      // If the broadcast document was created through the hydration process, then it would have been added
      // as a Json document, and we must now convert it to a document of the given type.
      if (_isDocumentPersistenceEnabled(doc)) {
        _validateDataSerialization<T>(
          fromJson: fromJson,
          toJson: toJson,
          data: doc.get()?.data,
        );
      }

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
    return _instance._broadcastCollectionStore.containsKey(query.collection);
  }

  bool _isDocumentPendingBroadcast<T>(Document<T> doc) {
    return _instance._broadcastCollectionStore[doc.collection]
            ?.containsKey(doc.id) ??
        false;
  }

  void _broadcast({
    bool broadcastPersistor = true,
  }) {
    for (final observer in _broadcastObservers) {
      observer._onBroadcast();
    }

    for (final broadcastCollection in _broadcastCollectionStore.values) {
      if (persistor != null && broadcastPersistor) {
        persistor!.onBroadcast(
          broadcastCollection.values
              // Touched documents do not need to be re-persisted since their data has not changed.
              .where((broadcastDoc) =>
                  broadcastDoc.type != BroadcastEventTypes.touched)
              .toList(),
        );
      }

      broadcastCollection.clear();
    }
  }

  DocumentSnapshot<T> _writeSnapshot<T>(
    Document<T> doc,
    T data, {
    bool broadcast = true,
  }) {
    if (data is! Json && _isDocumentPersistenceEnabled(doc)) {
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

    // Build the updated set of dependencies for this document.
    _buildDependencies(snap);

    if (broadcast) {
      _writeBroadcastDocument<T>(doc, eventType);
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
    if (doc.exists()) {
      _collectionStore[doc.collection]!.remove(doc.id);

      if (broadcast) {
        _writeBroadcastDocument<T>(doc, BroadcastEventTypes.removed);
      }
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

  /// Rebuilds a set of dependencies that the snapshot's document is dependent on
  /// whenever a document emits a new snapshot.
  void _buildDependencies<T>(DocumentSnapshot<T> snap) {
    final dependenciesBuilder = snap.doc.dependenciesBuilder;

    if (dependenciesBuilder != null) {
      final dependencies = dependenciesBuilder(snap);

      for (final doc in dependencies) {
        if (!_dependenciesStore.containsKey(doc)) {
          _dependenciesStore[doc] = {};
        }
        _dependenciesStore[doc]!.add(snap.doc);
      }
    }
  }

  /// Schedules all documents that depend on the given document for rebroadcast. This occurs
  /// for any type of broadcast (added, modified, removed or touched).
  void _rebroadcastDependents(BroadcastDocument doc) {
    final eventType = doc.type;
    final dependentDocs = _dependenciesStore[doc];

    if (dependentDocs != null) {
      // Clone the dependencies set to a list so that the set can be altered during iteration.
      for (final doc in dependentDocs.toList()) {
        if (doc.exists()) {
          rebroadcast(doc);
          // If the document that registered as a dependency no longer exits, then it is lazily
          // removed from this document's dependents.
        } else if (eventType == BroadcastEventTypes.removed) {
          dependentDocs.remove(doc);
        }
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
      final data = await _instance.persistor!.hydrate();

      for (final collectionDataStoreEntry in data.entries) {
        final collection = collectionDataStoreEntry.key;
        final documentDataStore = collectionDataStoreEntry.value;

        for (final documentDataEntry in documentDataStore.entries) {
          _instance._writeSnapshot<Json>(
            Document<Json>(collection: collection, id: documentDataEntry.key),
            documentDataEntry.value,
            broadcast: false,
          );
        }
      }
    } catch (e) {
      // ignore: avoid_print
      print('Loon: Error hydrating');
    } finally {
      _isHydrating = false;
    }
    _instance._broadcast(broadcastPersistor: false);
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

  static Future<void> clearAll() {
    return Loon._instance._clearAll();
  }

  /// Enqueues a document to be rebroadcasted, updating all listeners that are subscribed to that document.
  static void rebroadcast(Document doc) {
    _instance._writeBroadcastDocument(
      doc,
      BroadcastEventTypes.touched,
    );
  }
}
