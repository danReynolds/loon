library loon;

import 'dart:async';

export 'widgets/query_stream_builder.dart';
export 'widgets/document_stream_builder.dart';
export 'persistor/file_persistor.dart';
export 'persistor/encrypted_file_persistor.dart';

part 'observable.dart';
part 'broadcast_observable.dart';
part 'query.dart';
part 'observable_query.dart';
part 'collection.dart';
part 'document.dart';
part 'observable_document.dart';
part 'types.dart';
part 'document_snapshot.dart';
part 'persistor/persistor.dart';
part 'computable.dart';
part 'computation.dart';
part 'observable_computation.dart';

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

  /// The list of observers, either document or query observers, that should be notified on broadcast.
  final Set<BroadcastObservable> _broadcastObservers = {};

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
    // of the document is cached for efficient repeat access.
    return _writeSnapshot<T>(doc, fromJson!(snap.data));
  }

  /// Returns whether a collection name exists in the collection data store.
  bool _hasCollection(String collection) {
    return _collectionStore.containsKey(collection);
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
      );
    }).toList();
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
      if (doc is BroadcastDocument<T>) {
        return doc;
      } else {
        // If the broadcast document was created through the hydration process, then it would have been added
        // as a Json document, and we must now convert it to a document of the given type.
        _validateDataSerialization<T>(
          fromJson: fromJson,
          toJson: toJson,
          data: doc.get()?.data,
        );

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
    }).toList();
  }

  void _addBroadcastObserver(BroadcastObservable observer) {
    _broadcastObservers.add(observer);
  }

  void _removeBroadcastObserver(BroadcastObservable observer) {
    _broadcastObservers.remove(observer);
  }

  void _scheduleBroadcast() {
    if (!_hasPendingBroadcast) {
      _hasPendingBroadcast = true;

      // Schedule a broadcast event to be run on the microtask queue.
      scheduleMicrotask(() {
        _broadcastQueries();
        _hasPendingBroadcast = false;
      });
    }
  }

  bool _isScheduledForBroadcast<T>(Document<T> doc) {
    return _instance._broadcastCollectionStore[doc.collection]
            ?.containsKey(doc.id) ??
        false;
  }

  void _broadcastQueries({
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
    if (data is! Json) {
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

    _writeBroadcastDocument<T>(
      doc,
      _hasDocument(doc)
          ? BroadcastEventTypes.modified
          : BroadcastEventTypes.added,
    );

    final snap = _collectionStore[doc.collection]![doc.id] =
        DocumentSnapshot<T>(doc: doc, data: data);

    if (broadcast) {
      _scheduleBroadcast();
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
    return _writeSnapshot<T>(doc, data, broadcast: broadcast);
  }

  DocumentSnapshot<T> _modifyDocument<T>(
    Document<T> doc,
    ModifyFn<T> modifyFn, {
    bool broadcast = true,
  }) {
    return _writeSnapshot<T>(doc, modifyFn(doc.get()), broadcast: broadcast);
  }

  void _deleteDocument<T>(
    Document<T> doc, {
    bool broadcast = true,
  }) {
    if (doc.exists()) {
      _collectionStore[doc.collection]!.remove(doc.id);
      _writeBroadcastDocument<T>(doc, BroadcastEventTypes.removed);

      if (broadcast) {
        _scheduleBroadcast();
      }
    }
  }

  void _writeBroadcastDocument<T>(
    Document<T> doc,
    BroadcastEventTypes eventType,
  ) {
    if ((eventType == BroadcastEventTypes.modified ||
            eventType == BroadcastEventTypes.touched) &&
        !doc.exists()) {
      return;
    }

    if (!_broadcastCollectionStore.containsKey(doc.collection)) {
      _broadcastCollectionStore[doc.collection] = {};
    }

    _instance._broadcastCollectionStore[doc.collection]![doc.id] =
        BroadcastDocument<T>(
      doc,
      eventType,
    );
  }

  static void configure({
    Persistor? persistor,
  }) {
    if (persistor != null) {
      _instance.persistor = persistor;
    }
  }

  static Future<void> hydrate() async {
    if (_instance.persistor == null) {
      return;
    }
    try {
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
    }
    _instance._broadcastQueries(broadcastPersistor: false);
  }

  static Collection<T> collection<T>(
    String collection, {
    FromJson<T>? fromJson,
    ToJson<T>? toJson,
    PersistorSettings<T>? persistorSettings,
  }) {
    return Collection<T>(
      collection,
      fromJson: fromJson,
      toJson: toJson,
      persistorSettings: persistorSettings,
    );
  }

  static Document<T> doc<T>(
    String id, {
    FromJson<T>? fromJson,
    ToJson<T>? toJson,
    PersistorSettings<T>? persistorSettings,
  }) {
    return collection<T>(
      '__ROOT__$id',
      fromJson: fromJson,
      toJson: toJson,
      persistorSettings: persistorSettings,
    ).doc(id);
  }

  static Future<void> clearAll() {
    return Loon._instance._clearAll();
  }

  /// Enqueues a document to be rebroadcasted, updating all streams that are subscribed to that document.
  static void rebroadcast<T>(Document<T> doc) {
    // If the document is already scheduled for broadcast, then manually touching it for rebroadcast is a no-op, since it
    // is already enqueued for broadcast.
    if (!_instance._isScheduledForBroadcast(doc)) {
      _instance._writeBroadcastDocument<T>(
        doc,
        BroadcastEventTypes.touched,
      );
      _instance._scheduleBroadcast();
    }
  }
}
