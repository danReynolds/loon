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

typedef SerializedDocumentDataStore = Map<String, Json>;
typedef ParsedCollectionDataStore = Map<String, Map<String, dynamic>>;
typedef SerializedCollectionDataStore
    = Map<String, SerializedDocumentDataStore>;
typedef BroadcastCollectionDataStore
    = Map<String, Map<String, BroadcastDocument>>;

class Loon {
  Persistor? persistor;

  static final Loon _instance = Loon._();

  Loon._();

  /// Document data is stored in both a serialized and de-serialized collection data store. The serialized document data store is required for 3 reasons:
  /// 1. This is essential for hydrating document data from persistent storage, since hydration can only restore serialized data and
  /// does not know how to parse document data into a de-serialized representation.
  /// 2. It also improves the performance of persisting data, enabling updated data to only ever be serialized once.
  /// 3. It allows document data to be read with or without a [fromJson] de-serializer.
  ///
  /// The de-serialized document data store is necessary in order to improve the performance of repeatedly reading document data.
  /// The de-serialized data store sits in front of the serialized data and can return the de-serialized representation without the performance hit of
  /// repeated de-serialization.
  final SerializedCollectionDataStore _serializedCollectionDataStore = {};
  final ParsedCollectionDataStore _parsedCollectionDataStore = {};

  final BroadcastCollectionDataStore _broadcastCollectionDataStore = {};

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

  Json? _getSerializedDocumentData(Document doc) {
    return _serializedCollectionDataStore[doc.collection]?[doc.id];
  }

  T? _getParsedDocumentData<T>(Document<T> doc) {
    return _parsedCollectionDataStore[doc.collection]?[doc.id];
  }

  T? _getDocumentData<T>(Document<T> doc) {
    final fromJson = doc.fromJson;
    final serializedData = _getSerializedDocumentData(doc);

    _validateTypeSerialization<T>(
      fromJson: doc.fromJson,
      toJson: doc.toJson,
    );

    if (serializedData != null && fromJson != null) {
      final cachedData = _getParsedDocumentData<T>(doc);

      if (cachedData != null) {
        return cachedData;
      }

      final parsedData = fromJson(serializedData);
      _cacheParsedDocumentData(doc, parsedData);
      return parsedData;
    }
    return serializedData as T?;
  }

  bool _hasCollection(String collection) {
    return _serializedCollectionDataStore.containsKey(collection);
  }

  void _clearCollection(String collection) {
    if (_hasCollection(collection)) {
      _serializedCollectionDataStore.remove(collection);
      _scheduleBroadcast();

      if (persistor != null) {
        persistor!.clear(collection);
      }
    }
  }

  Future<void> _clearAll() async {
    if (_serializedCollectionDataStore.isEmpty) {
      return;
    }

    _serializedCollectionDataStore.clear();
    _scheduleBroadcast();

    if (persistor != null) {
      return persistor!.clearAll();
    }
  }

  void _initializeCollection(String collection) {
    _serializedCollectionDataStore[collection] = {};
    _broadcastCollectionDataStore[collection] = {};
  }

  bool _hasDocument(Document doc) {
    final collection = doc.collection;

    return _hasCollection(collection) &&
        _serializedCollectionDataStore[collection]!.containsKey(doc.id);
  }

  List<Document<T>> _getDocuments<T>(
    String collection, {
    FromJson<T>? fromJson,
    ToJson<T>? toJson,
    PersistorSettings<T>? persistorSettings,
  }) {
    if (!_hasCollection(collection)) {
      _initializeCollection(collection);
    }
    return _serializedCollectionDataStore[collection]!.entries.map((entry) {
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
    if (!_broadcastCollectionDataStore.containsKey(collection)) {
      return [];
    }

    return _broadcastCollectionDataStore[collection]!.values.map((doc) {
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
    return _instance._broadcastCollectionDataStore[doc.collection]!
        .containsKey(doc.id);
  }

  void _broadcastQueries({
    bool broadcastPersistor = true,
  }) {
    for (final observer in _broadcastObservers) {
      observer._onBroadcast();
    }

    for (final broadcastCollection in _broadcastCollectionDataStore.values) {
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

  void _cacheParsedDocumentData<T>(Document<T> doc, T data) {
    final collection = doc.collection;

    if (!_parsedCollectionDataStore.containsKey(collection)) {
      _parsedCollectionDataStore[collection] = {};
    }

    _parsedCollectionDataStore[doc.collection]![doc.id] = data;
  }

  DocumentSnapshot<T> _writeDocument<T>(
    Document<T> doc,
    T data, {
    bool broadcast = true,
  }) {
    final docId = doc.id;
    final collection = doc.collection;
    final toJson = doc.toJson;

    if (!_hasCollection(collection)) {
      _initializeCollection(collection);
    }

    final isNewDocument = !_hasDocument(doc);

    if (data is Json) {
      _serializedCollectionDataStore[collection]![docId] = data;
    } else {
      _validateDataSerialization<T>(
        fromJson: doc.fromJson,
        toJson: toJson,
        data: data,
      );
      _cacheParsedDocumentData<T>(doc, data);
      _serializedCollectionDataStore[collection]![docId] = toJson!(data);
    }

    _broadcastCollectionDataStore[collection]![docId] = BroadcastDocument<T>(
      doc,
      isNewDocument ? BroadcastEventTypes.added : BroadcastEventTypes.modified,
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
      _serializedCollectionDataStore[doc.collection]!.remove(doc.id);
      _broadcastCollectionDataStore[doc.collection]![doc.id] =
          BroadcastDocument<T>(
        doc,
        BroadcastEventTypes.removed,
      );

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
      final SerializedCollectionDataStore data =
          await _instance.persistor!.hydrate();

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

  /// Enqueues a document to be rebroadcasted, updating all streams that are subscribed to that document.
  static void rebroadcast<T>(Document<T> doc) {
    if (!doc.exists()) {
      return;
    }

    // If the document is already scheduled for broadcast, then manually touching it for rebroadcast is a no-op, since it
    // is aleady enqueued for broadcast.
    if (!_instance._isScheduledForBroadcast(doc)) {
      _instance._broadcastCollectionDataStore[doc.collection]![doc.id] =
          BroadcastDocument<T>(
        doc,
        BroadcastEventTypes.touched,
      );

      _instance._scheduleBroadcast();
    }
  }
}
