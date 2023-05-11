library loon;

import 'dart:async';
import 'package:uuid/uuid.dart';

export 'widgets/stream_query_builder.dart';
export 'persistor/file_persistor.dart';

part 'watch_query.dart';
part 'query.dart';
part 'collection.dart';
part 'document.dart';
part 'types.dart';
part 'document_snapshot.dart';
part 'persistor/persistor.dart';

const uuid = Uuid();

typedef DocumentDataStore = Map<String, Json>;
typedef CollectionDataStore = Map<String, DocumentDataStore>;
typedef BroadcastCollectionDataStore
    = Map<String, Map<String, BroadcastDocument>>;

class Loon {
  Persistor? persistor;

  static final Loon instance = Loon._();

  Loon._();

  final CollectionDataStore _collectionDataStore = {};

  final BroadcastCollectionDataStore _broadcastCollectionDataStore = {};

  final Map<String, WatchQuery<dynamic>> _watchQueryStore = {};

  bool _hasPendingBroadcast = false;

  Json? _getSerializedDocumentData(Document doc) {
    return _collectionDataStore[doc.collection]?[doc.id];
  }

  T? _getDocumentData<T>(Document<T> doc) {
    final fromJson = doc.fromJson;
    final serializedData = _getSerializedDocumentData(doc);

    if (serializedData != null && fromJson != null) {
      return fromJson(serializedData);
    }
    return serializedData as T?;
  }

  bool _hasCollection(String collection) {
    return _collectionDataStore.containsKey(collection);
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
        if (fromJson == null || toJson == null) {
          throw Exception('Missing fromJson/toJson serializer');
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
    }).toList();
  }

  void _registerWatchQuery(WatchQuery query) {
    _watchQueryStore[query.queryId] = query;
  }

  void _unregisterWatchQuery(WatchQuery query) {
    _watchQueryStore.remove(query.queryId);
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
    for (final watchQuery in _watchQueryStore.values) {
      watchQuery._onBroadcast();
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

    if (T == Json) {
      _collectionDataStore[collection]![docId] = data as Json;
    } else {
      if (toJson == null) {
        throw Exception('Missing fromJson/toJson serializer');
      }
      _collectionDataStore[collection]![docId] = toJson(data);
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
    return modifyFn(doc.get()?.data);
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
      instance.persistor = persistor;
      instance._hydrate();
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
    } finally {
      _broadcastQueries(broadcastPersistor: false);
    }
  }

  static Collection<T> collection<T>(
    String collection, {
    FromJson<T>? fromJson,
    ToJson<T>? toJson,
    PersistorSettings<T>? persistorSettings,
  }) {
    if (T is! Json && (fromJson == null || toJson == null)) {
      throw Exception('Missing fromJson/toJson serializer');
    }

    return Collection<T>(
      collection,
      fromJson: fromJson,
      toJson: toJson,
      persistorSettings: persistorSettings,
    );
  }
}
