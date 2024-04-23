library loon;

import 'dart:async';
import 'package:flutter/foundation.dart';

export 'widgets/query_stream_builder.dart';
export 'widgets/document_stream_builder.dart';
export 'persistor/file_persistor/file_persistor.dart';

part 'dep_store.dart';
part 'value_store.dart';
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
part 'broadcast_manager.dart';
part 'utils.dart';

class Loon {
  Persistor? persistor;

  static final Loon _instance = Loon._();

  Loon._();

  /// The store of document snapshots indexed by their document path.
  final documentStore = ValueStore<DocumentSnapshot>();

  /// The store of dependencies of documents.
  final Map<Document, Set<Document>> dependenciesStore = {};

  /// The store of dependents of documents.
  final Map<Document, Set<Document>> dependentsStore = {};

  final broadcastManager = BroadcastManager();

  bool enableLogging = false;

  bool get _isGlobalPersistenceEnabled {
    return persistor?.settings.persistenceEnabled ?? false;
  }

  DocumentSnapshot<T>? getSnapshot<T>(Document<T> doc) {
    return documentStore.get(doc.path) as DocumentSnapshot<T>?;
  }

  List<DocumentSnapshot<T>> getSnapshots<T>(Collection<T> collection) {
    return List<DocumentSnapshot<T>>.from(
      documentStore.getAll(collection.path)?.values.toList() ?? [],
    );
  }

  DocumentSnapshot<T> writeDocument<T>(
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

    if (broadcast) {
      broadcastManager.writeDocument(doc, event);
    }

    final snap = DocumentSnapshot(
      doc: doc,
      data: data,
    );
    updateDependencies(snap);

    documentStore.write(doc.path, snap);

    if (persist && doc.isPersistenceEnabled()) {
      persistor!._persistDoc(doc);
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
        event: EventTypes.added,
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
      persistor!._persistDoc(doc);
    }
  }

  void deleteCollection(Collection collection) {
    final path = collection.path;
    broadcastManager.deleteCollection(collection);
    documentStore.delete(path);
    // persistor?.delete(path);
  }

  /// On write of a snapshot, the dependencies manager updates the dependencies
  /// store with the updated document dependencies and
  void updateDependencies(DocumentSnapshot snap) {
    final doc = snap.doc;
    final prevDeps = dependenciesStore[doc];
    final deps = doc.dependenciesBuilder?.call(snap);

    if (setEquals(deps, prevDeps)) {
      return;
    }

    if (deps != null && prevDeps != null) {
      dependenciesStore[doc] = deps;

      final addedDeps = deps.difference(prevDeps);
      final removedDeps = prevDeps.difference(deps);

      for (final dep in addedDeps) {
        (dependentsStore[dep] ??= {}).add(doc);
      }
      for (final dep in removedDeps) {
        dependentsStore[dep]!.remove(doc);
      }
    } else if (deps != null) {
      dependenciesStore[doc] = deps;
      for (final dep in deps) {
        (dependentsStore[dep] ??= {}).add(doc);
      }
    } else if (prevDeps != null) {
      dependenciesStore.remove(doc);
      for (final dep in prevDeps) {
        dependentsStore[dep]!.remove(doc);
      }
    }
  }

  /// Clears all data from the store.
  Future<void> _clearAll({
    bool broadcast = true,
  }) async {
    // Clear the store.
    documentStore.clear();
    // Clear any documents scheduled for broadcast, as whatever events happened prior to the clear are now irrelevant.
    broadcastManager.clear();

    // Clear all dependencies and dependents of documents.
    dependenciesStore.clear();
    dependentsStore.clear();

    return persistor?._clearAll();
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
          _instance.writeDocument(
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
    _instance.broadcastManager.writeDocument(doc, EventTypes.touched);
  }

  /// Returns a Map of all of the data and metadata of the store for debugging and inspection purposes.
  static Json inspect() {
    return {
      "store": _instance.documentStore.inspect(),
      "broadcastStore": _instance.broadcastManager.inspect(),
      "dependencyStore": _instance.dependenciesStore,
      "dependentsStore": _instance.dependentsStore,
    };
  }

  static bool get isLoggingEnabled {
    return _instance.enableLogging;
  }
}
