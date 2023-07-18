library loon;

import 'dart:async';

export 'widgets/query_stream_builder.dart';
export 'widgets/document_stream_builder.dart';
export 'persistor/file_persistor.dart';
export 'persistor/encrypted_file_persistor.dart';

part 'broadcast_observable.dart';
part 'query.dart';
part 'observable_query.dart';
part 'collection.dart';
part 'document.dart';
part 'observable_document.dart';
part 'types.dart';
part 'document_snapshot.dart';
part 'persistor/persistor.dart';

typedef CollectionDataStore = Map<String, Map<String, dynamic>>;
typedef BroadcastCollectionStore = Map<String, Map<String, BroadcastDocument>>;

class Loon {
  Persistor? persistor;

  static final Loon _instance = Loon._();

  Loon._();

  /// Document data is stored in a dynamic collection mixing both serialized and parsed data. Documents are initially hydrated in their serialized
  /// representation, since de-serializers cannot be known ahead of time. They are then cached in their parsed representation when they are first accessed
  /// using a serializer. Caching the parsed document data is necessary in order to improve the performance of repeatedly reading document data.
  final CollectionDataStore _collectionDataStore = {};

  final BroadcastCollectionStore _broadcastCollectionStore = {};
  final Set<BroadcastObservable> _broadcastObservers = {};

  bool _hasPendingBroadcast = false;

  static void _validateDataSerialization<T>({
    required FromJson<T>? fromJson,
    required ToJson<T>? toJson,
    required T? data,
  }) {
    if (data is! Json? && (fromJson == null || toJson == null)) {
      throw Exception('Missing fromJson/toJson serializer');
    }
  }

  static void _validateTypeSerialization<T>({
    required FromJson<T>? fromJson,
    required ToJson<T>? toJson,
  }) {
    if (T != Json && T != dynamic && (fromJson == null || toJson == null)) {
      throw Exception('Missing fromJson/toJson serializer');
    }
  }

  T? _getDocumentData<T>(Document<T> doc) {
    final fromJson = doc.fromJson;
    dynamic documentData = _collectionDataStore[doc.collection]?[doc.id];

    _validateTypeSerialization<T>(
      fromJson: doc.fromJson,
      toJson: doc.toJson,
    );

    // Upon first read of serialized data using a serializer, the parsed representation
    // of the document is cached for efficient repeat access.
    if (documentData != null && fromJson != null && documentData is Json) {
      return _writeDocumentData<T>(doc, fromJson(documentData));
    }
    return documentData as T?;
  }

  bool _hasCollection(String collection) {
    return _collectionDataStore.containsKey(collection);
  }

  void _clearCollection(String collection) {
    if (_hasCollection(collection)) {
      _collectionDataStore.remove(collection);
      _scheduleBroadcast();

      if (persistor != null) {
        persistor!.clear(collection);
      }
    }
  }

  Future<void> _clearAll() async {
    if (_collectionDataStore.isEmpty) {
      return;
    }

    _collectionDataStore.clear();
    _scheduleBroadcast();

    if (persistor != null) {
      return persistor!.clearAll();
    }
  }

  bool _hasDocument(Document doc) {
    return _collectionDataStore[doc.collection]?.containsKey(doc.id) ?? false;
  }

  List<Document<T>> _getDocuments<T>(
    String collection, {
    FromJson<T>? fromJson,
    ToJson<T>? toJson,
    PersistorSettings<T>? persistorSettings,
  }) {
    if (!_hasCollection(collection)) {
      return [];
    }

    return _collectionDataStore[collection]!.entries.map((entry) {
      return Document<T>(
        collection: collection,
        id: entry.key,
        fromJson: fromJson,
        toJson: toJson,
        persistorSettings: persistorSettings,
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

  void addBroadcastObserver(BroadcastObservable observer) {
    _broadcastObservers.add(observer);
  }

  void removeBroadcastObserver(BroadcastObservable observer) {
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

  T _writeDocumentData<T>(Document<T> doc, T data) {
    final collection = doc.collection;

    if (!_collectionDataStore.containsKey(collection)) {
      _collectionDataStore[collection] = {};
    }

    return _collectionDataStore[doc.collection]![doc.id] = data;
  }

  DocumentSnapshot<T> _writeDocument<T>(
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

    _writeDocumentData<T>(doc, data);
    _writeBroadcastDocument<T>(
      doc,
      _hasDocument(doc)
          ? BroadcastEventTypes.modified
          : BroadcastEventTypes.added,
    );

    if (broadcast) {
      _scheduleBroadcast();
    }

    return doc.get()!;
  }

  DocumentSnapshot<T> _addDocument<T>(
    Document<T> doc,
    T data, {
    bool broadcast = true,
  }) {
    if (_hasDocument(doc)) {
      throw Exception('Cannot add duplicate document');
    }

    return _writeDocument<T>(doc, data);
  }

  DocumentSnapshot<T> _updateDocument<T>(
    Document<T> doc,
    T data, {
    bool broadcast = true,
  }) {
    return _writeDocument<T>(doc, data);
  }

  DocumentSnapshot<T> _modifyDocument<T>(
    Document<T> doc,
    ModifyFn<T> modifyFn, {
    bool broadcast = true,
  }) {
    return _writeDocument<T>(doc, modifyFn(doc.get()));
  }

  void _deleteDocument<T>(
    Document<T> doc, {
    bool broadcast = true,
  }) {
    if (doc.exists()) {
      _collectionDataStore[doc.collection]!.remove(doc.id);
      _writeBroadcastDocument<T>(doc, BroadcastEventTypes.removed);

      if (broadcast) {
        _scheduleBroadcast();
      }
    }
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
      final CollectionDataStore data = await _instance.persistor!.hydrate();

      for (final collectionDataStoreEntry in data.entries) {
        final collection = collectionDataStoreEntry.key;
        final documentDataStore = collectionDataStoreEntry.value;

        for (final documentDataEntry in documentDataStore.entries) {
          _instance._writeDocument<Json>(
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
      '__ROOT__',
      fromJson: fromJson,
      toJson: toJson,
      persistorSettings: persistorSettings,
    ).doc(id);
  }

  static Future<void> clearAll() {
    return Loon._instance._clearAll();
  }

  void _writeBroadcastDocument<T>(
    Document<T> doc,
    BroadcastEventTypes eventType,
  ) {
    if (eventType != BroadcastEventTypes.removed && !doc.exists()) {
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
