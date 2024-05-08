library loon;

import 'dart:async';
import 'package:flutter/foundation.dart';

export 'widgets/query_stream_builder.dart';
export 'widgets/document_stream_builder.dart';
export 'persistor/file_persistor/file_persistor.dart';

part 'store/path_ref_store.dart';
part 'store/indexed_value_store.dart';
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
part 'logger.dart';

class Loon {
  Persistor? persistor;

  static final Loon _instance = Loon._();

  Loon._();

  /// The store of document snapshots indexed by their document path.
  final documentStore = IndexedValueStore<DocumentSnapshot>();

  /// The store of dependencies of documents.
  final dependenciesStore = IndexedValueStore<Set<Document>>();

  /// The store of dependents of documents.
  final Map<Document, Set<Document>> dependentsStore = {};

  final broadcastManager = BroadcastManager();

  static final logger = Logger('Loon');

  bool enableLogging = false;

  bool get _isGlobalPersistenceEnabled {
    return persistor?.settings.persistenceEnabled ?? false;
  }

  // When a document is read, if it is still in JSON format from hydration and is now being accessed
  // with a serializer, then it is de-serialized at time of access.
  DocumentSnapshot<T> parseSnap<T>(
    DocumentSnapshot snap, {
    required FromJson<T>? fromJson,
    required ToJson<T>? toJson,
    required PersistorSettings<T>? persistorSettings,
    required DependenciesBuilder<T>? dependenciesBuilder,
  }) {
    if (snap is DocumentSnapshot<Json> && T != Json && T != dynamic) {
      _validateTypeSerialization<T>(
        fromJson: fromJson,
        toJson: toJson,
      );
      final doc = snap.doc;

      return writeDocument<T>(
        Document<T>(
          doc.parent,
          doc.id,
          fromJson: fromJson,
          toJson: toJson,
          persistorSettings: persistorSettings,
          dependenciesBuilder: dependenciesBuilder,
        ),
        fromJson!(snap.data),
        event: EventTypes.modified,
        broadcast: false,
        persist: false,
      );
    }

    return snap as DocumentSnapshot<T>;
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
        .getAll(collection.path)
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
    dependenciesStore.delete(path);
    persistor?._clear(collection);
  }

  /// On write of a snapshot, the dependencies manager updates the dependencies
  /// store with the updated document dependencies and
  void updateDependencies<T>(DocumentSnapshot<T> snap) {
    final doc = snap.doc;
    final prevDeps = dependenciesStore.get(doc.path);
    final deps = doc.dependenciesBuilder?.call(snap);

    if (setEquals(deps, prevDeps)) {
      return;
    }

    if (deps != null && prevDeps != null) {
      final addedDeps = deps.difference(prevDeps);
      final removedDeps = prevDeps.difference(deps);

      for (final dep in addedDeps) {
        (dependentsStore[dep] ??= {}).add(doc);
      }
      for (final dep in removedDeps) {
        if (dependentsStore[dep]!.length == 1) {
          dependentsStore.remove(dep);
        } else {
          dependentsStore[dep]!.remove(doc);
        }
      }

      if (deps.isEmpty) {
        dependenciesStore.delete(doc.path);
      } else {
        dependenciesStore.write(doc.path, deps);
      }
    } else if (deps != null) {
      dependenciesStore.write(doc.path, deps);
      for (final dep in deps) {
        (dependentsStore[dep] ??= {}).add(doc);
      }
    } else if (prevDeps != null) {
      dependenciesStore.delete(doc.path);
      for (final dep in prevDeps) {
        if (dependentsStore[dep]!.length == 1) {
          dependentsStore.remove(dep);
        } else {
          dependentsStore[dep]!.remove(doc);
        }
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

  static Future<void> hydrate([List<Collection>? collections]) async {
    if (_instance.persistor == null) {
      logger.log('Hydration skipped - no persistor specified');
      return;
    }
    try {
      final data = await _instance.persistor!._hydrate(collections);

      for (final entry in data.entries) {
        final docPath = entry.key;
        final data = entry.value;

        _instance.writeDocument<Json>(
          Document.fromPath(docPath),
          data,
          event: EventTypes.hydrated,
          persist: false,
        );
      }
    } catch (e) {
      // ignore: avoid_print
      logger.log('Error hydrating');
      rethrow;
    }
  }

  static Document<T> doc<T>(
    String id, {
    FromJson<T>? fromJson,
    ToJson<T>? toJson,
    PersistorSettings<T>? persistorSettings,
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
    PersistorSettings<T>? persistorSettings,
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
      "dependencyStore": _instance.dependenciesStore.inspect(),
      "dependentsStore": _instance.dependentsStore,
    };
  }

  static bool get isLoggingEnabled {
    return _instance.enableLogging;
  }

  static PersistorSettings? get persistorSettings {
    return _instance.persistor?.settings;
  }
}
