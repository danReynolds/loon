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

typedef DocumentDataStore = Map<String, Json>;
typedef CollectionDataStore = Map<String, DocumentDataStore>;
typedef BroadcastCollectionDataStore
    = Map<String, Map<String, BroadcastDocument>>;

class Loon {
  Persistor? persistor;

  static final Loon _instance = Loon._();

  Loon._();

  final CollectionDataStore _collectionDataStore = {};

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
    return _collectionDataStore[doc.collection]?[doc.id];
  }

  T? _getDocumentData<T>(Document<T> doc) {
    final fromJson = doc.fromJson;
    final serializedData = _getSerializedDocumentData(doc);

    _validateTypeSerialization<T>(
      fromJson: doc.fromJson,
      toJson: doc.toJson,
    );

    if (serializedData != null && fromJson != null) {
      return fromJson(serializedData);
    }
    return serializedData as T?;
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

  void _initializeCollection(String collection) {
    _collectionDataStore[collection] = {};
    _broadcastCollectionDataStore[collection] = {};
  }

  bool _hasDocument(Document doc) {
    final collection = doc.collection;

    return _hasCollection(collection) &&
        _collectionDataStore[collection]!.containsKey(doc.id);
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

  void _broadcastQueries({
    bool broadcastPersistor = true,
  }) {
    for (final observer in _broadcastObservers) {
      observer._onBroadcast();
    }
    for (final broadcastCollection in _broadcastCollectionDataStore.values) {
      if (persistor != null && broadcastPersistor) {
        persistor!.onBroadcast(broadcastCollection.values.toList());
      }

      broadcastCollection.clear();
    }
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
      _collectionDataStore[collection]![docId] = data;
    } else {
      _validateDataSerialization<T>(
        fromJson: doc.fromJson,
        toJson: toJson,
        data: data,
      );
      _collectionDataStore[collection]![docId] = toJson!(data);
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
      _collectionDataStore[doc.collection]!.remove(doc.id);
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
      _instance._hydrate();
    }
  }

  Future<void> _hydrate() async {
    if (persistor == null) {
      return;
    }
    try {
      final CollectionDataStore data = await persistor!.hydrate();

      for (final collectionDataStoreEntry in data.entries) {
        final collection = collectionDataStoreEntry.key;
        final documentDataStore = collectionDataStoreEntry.value;

        for (final documentDataEntry in documentDataStore.entries) {
          _writeDocument<Json>(
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
    _broadcastQueries(broadcastPersistor: false);
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

  static Document<T> doc<T>(String id) {
    return collection<T>('__ROOT__').doc(id);
  }

  static Future<void> clearAll() {
    return Loon._instance._clearAll();
  }
}
