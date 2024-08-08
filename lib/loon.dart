library loon;

import 'dart:async';
import 'package:flutter/foundation.dart';
import 'package:uuid/uuid.dart';
import 'dart:collection';

export 'widgets/query_stream_builder.dart';
export 'widgets/document_stream_builder.dart';
export 'persistor/file_persistor/file_persistor.dart';

part 'store/path_ref_store.dart';
part 'store/value_store.dart';
part 'broadcast_observer.dart';
part 'query.dart';
part 'observable_query.dart';
part 'collection.dart';
part 'document.dart';
part 'observable_document.dart';
part 'types.dart';
part 'document_snapshot.dart';
part 'document_change_snapshot.dart';
part 'broadcast_manager.dart';
part 'dependency_manager.dart';
part 'utils/validation.dart';
part 'utils/logger.dart';
part 'store_reference.dart';
part 'utils/exceptions.dart';
part 'persistor/persistor.dart';
part 'persistor/operations.dart';
part 'persistor/persist_manager.dart';
part 'extensions/iterable.dart';

class Loon {
  static final Loon _instance = Loon._();

  Loon._() {
    _logger = Logger('Loon', output: (message) {
      if (_isLoggingEnabled && kDebugMode) {
        // ignore: avoid_print
        print(message);
      }
    });
  }

  /// The store of document snapshots indexed by document path.
  final documentStore = ValueStore<DocumentSnapshot>();

  final broadcastManager = BroadcastManager();

  final dependencyManager = DependencyManager();

  PersistManager? persistManager;

  late final Logger _logger;

  bool _isLoggingEnabled = false;

  bool get _isGlobalPersistenceEnabled {
    return persistManager?.settings.enabled ?? false;
  }

  // When a document is read, if it is still in JSON format from hydration and is now being accessed
  // with a serializer, then it is de-serialized at time of access.
  DocumentSnapshot<T> parseSnap<T>(
    DocumentSnapshot snap, {
    required FromJson<T>? fromJson,
    required ToJson<T>? toJson,
    required PersistorSettings? persistorSettings,
    required DependenciesBuilder<T>? dependenciesBuilder,
  }) {
    if (snap is! DocumentSnapshot<T>) {
      final doc = snap.doc;
      final data = snap.data;

      _validateDataDeserialization<T>(doc: doc, fromJson: fromJson, data: data);

      return writeDocument<T>(
        Document<T>(
          doc.parent,
          doc.id,
          fromJson: fromJson,
          toJson: toJson,
          persistorSettings: persistorSettings,
          dependenciesBuilder: dependenciesBuilder,
        ),
        fromJson?.call(snap.data) ?? data as T,
        event: BroadcastEvents.modified,
        broadcast: false,
        persist: false,
      );
    }

    return snap;
  }

  bool existsSnap<T>(Document<T> doc) {
    return documentStore.hasValue(doc.path);
  }

  DocumentSnapshot<T>? getSnapshot<T>(Document<T> doc) {
    final snap = documentStore.get(doc.path);

    if (snap == null) {
      return null;
    }

    return parseSnap(
      snap,
      fromJson: doc.fromJson,
      toJson: doc.toJson,
      persistorSettings: doc.persistorSettings,
      dependenciesBuilder: doc.dependenciesBuilder,
    );
  }

  List<DocumentSnapshot<T>> getSnapshots<T>(Collection<T> collection) {
    final snaps = documentStore
        .getChildValues(collection.path)
        ?.values
        .map(
          (snap) => parseSnap(
            snap,
            fromJson: collection.fromJson,
            toJson: collection.toJson,
            persistorSettings: collection.persistorSettings,
            dependenciesBuilder: collection.dependenciesBuilder,
          ),
        )
        .toList();

    return List<DocumentSnapshot<T>>.from(snaps ?? []);
  }

  DocumentSnapshot<T> writeDocument<T>(
    Document<T> doc,
    T data, {
    required BroadcastEvents event,
    bool broadcast = true,
    bool persist = true,
  }) {
    if (broadcast) {
      broadcastManager.writeDocument(doc, event);
    }

    final snap = DocumentSnapshot(doc: doc, data: data);
    dependencyManager.updateDependencies(snap);

    documentStore.write(doc.path, snap);

    if (persist && doc.isPersistenceEnabled()) {
      _validateDataSerialization(
        doc: doc,
        data: data,
        toJson: doc.toJson,
      );

      persistManager?.persist(doc);
    }

    return snap;
  }

  List<DocumentSnapshot<T>> replaceCollection<T>(
    Collection<T> collection,
    List<DocumentSnapshot<T>> snaps,
  ) {
    deleteCollection(collection);

    for (final snap in snaps) {
      writeDocument(
        snap.doc,
        snap.data,
        event: BroadcastEvents.added,
      );
    }

    return snaps;
  }

  void deleteDocument<T>(Document<T> doc) {
    if (!doc.exists()) {
      return;
    }

    broadcastManager.deleteDocument(doc);
    documentStore.delete(doc.path);

    if (doc.isPersistenceEnabled()) {
      persistManager?.persist(doc);
    }
  }

  void deleteCollection(Collection collection) {
    final path = collection.path;
    broadcastManager.deleteCollection(collection);
    dependencyManager.deleteCollection(collection);
    documentStore.delete(path);
    persistManager?.clear(collection);
  }

  /// Clears all data from the store.
  Future<void> _clearAll({
    bool broadcast = true,
  }) async {
    // Clear the store.
    documentStore.clear();

    // Clear any documents scheduled for broadcast, as whatever events happened prior to the clear are now irrelevant.
    broadcastManager.clear();

    dependencyManager.clear();

    await persistManager?.clearAll();
  }

  static void configure({
    Persistor? persistor,
    bool enableLogging = false,
  }) {
    _instance._isLoggingEnabled = enableLogging;

    if (persistor != null) {
      _instance.persistManager = PersistManager(persistor: persistor);
    } else {
      _instance.persistManager = null;
    }
  }

  /// Hydrates persisted data from the store using the persistor specified in [Loon.configure].
  /// If no arguments are provided, then the entire store is hydrated by default. If specific
  /// [StoreReference] documents and collections are provided, then only data in the store under those
  /// references are hydrated.
  static Future<void> hydrate([List<StoreReference>? refs]) async {
    if (_instance.persistManager == null) {
      logger.log('Hydration skipped - persistence not enabled');
      return;
    }
    try {
      final data = await _instance.persistManager!.hydrate(refs);

      for (final entry in data.entries) {
        final docPath = entry.key;
        final data = entry.value;

        if (!_instance.documentStore.hasValue(docPath)) {
          _instance.writeDocument(
            Document.fromPath(docPath),
            data,
            event: BroadcastEvents.hydrated,
            persist: false,
          );
        }
      }
    } catch (e) {
      logger.log('Error hydrating');
      rethrow;
    }
  }

  static Document<T> doc<T>(
    String id, {
    FromJson<T>? fromJson,
    ToJson<T>? toJson,
    PersistorSettings? persistorSettings,
  }) {
    return collection<T>(
      _rootKey,
      fromJson: fromJson,
      toJson: toJson,
      persistorSettings: persistorSettings,
    ).doc(id);
  }

  static Collection<T> collection<T>(
    String name, {
    FromJson<T>? fromJson,
    ToJson<T>? toJson,
    PersistorSettings? persistorSettings,
    DependenciesBuilder<T>? dependenciesBuilder,
  }) {
    return Collection<T>(
      '',
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
    _instance.broadcastManager.writeDocument(doc, BroadcastEvents.touched);
  }

  /// Returns a Map of all of the data and metadata of the store for debugging and inspection purposes.
  static Json inspect() {
    return {
      "store": _instance.documentStore.inspect(),
      "broadcastStore": _instance.broadcastManager.inspect(),
      ..._instance.dependencyManager.inspect(),
    };
  }

  /// Unsubscribes all active observers of the store, disposing their stream resources.
  static void unsubscribe() {
    _instance.broadcastManager.unsubscribe();
  }

  static Logger get logger {
    return _instance._logger;
  }

  static PersistorSettings? get persistorSettings {
    return _instance.persistManager?.settings;
  }

  static Persistor? get persistor {
    return _instance.persistManager?.persistor;
  }
}
