import 'dart:async';
import 'dart:js_interop';

import 'package:loon/loon.dart';
import 'package:loon/persistor/data_store_manager.dart';
import 'package:loon/persistor/persistence_document.dart';
import 'package:web/web.dart';

class IndexedDBPersistor extends Persistor {
  static const _dbName = 'loon';
  static const _dbVersion = 1;

  late final DataStoreManager _manager;
  late final IDBDatabase _db;

  final _logger = Logger('IndexedDBPersistor');

  IndexedDBPersistor({
    super.settings = const PersistorSettings(),
    super.persistenceThrottle = const Duration(milliseconds: 100),
    super.onSync,
  });

  @override
  Future<void> init() async {
    final encrypter = await initEncrypter();

    final completer = Completer<void>();
    final request = window.indexedDB.open(_dbName, _dbVersion);
    request.onerror = ((error) {
      return completer.completeError(
        request.error?.message ?? 'unknown error initializing IndexedDB',
      );
    }).toJS;
    request.onsuccess = ((_) => completer.complete()).toJS;

    await completer.future;

    _db = request.result as IDBDatabase;

    _manager = DataStoreManager(
      encrypter: encrypter,
      persistenceThrottle: persistenceThrottle,
      onSync: onSync,
      onLog: _logger.log,
      settings: settings,
      resolver: resolver,
      index: index,
      factory: factory,
    );
  }

  @override
  Future<void> clear(List<Collection> collections) async {}

  @override
  Future<void> clearAll() {
    throw UnimplementedError();
  }

  @override
  Future<Json> hydrate([refs]) {
    throw UnimplementedError();
  }

  @override
  Future<void> persist(resolver, docs) {
    final resolver = ValueStore<String>();
    final List<PersistenceDocument> persistDocs = [];
    final globalPersistorSettings = Loon.persistorSettings;

    final defaultKey = switch (globalPersistorSettings) {
      PersistorSettings(key: PersistorValueKey key) => key,
      _ => Persistor.defaultKey,
    };
    resolver.write(ValueStore.root, defaultKey.value);

    for (final doc in docs) {
      bool encrypted = false;
      final persistorSettings = doc.persistorSettings;

      if (persistorSettings != null) {
        final persistorDoc = persistorSettings.doc;
        final docSettings = persistorSettings.settings;

        encrypted = docSettings.encrypted;

        switch (docSettings) {
          case PersistorSettings(key: PersistorValueKey key):
            String path;

            /// A value key is stored at the parent path of the document unless it is a document
            /// on the root collection via [Loon.doc], which should store keys under its own path.
            if (persistorDoc.parent != Collection.root.path) {
              path = persistorDoc.parent;
            } else {
              path = persistorDoc.path;
            }

            resolver.write(path, key.value);

            break;
          case PersistorSettings(key: PersistorBuilderKey keyBuilder):
            final snap = persistorDoc.get();
            final path = persistorDoc.path;

            if (snap != null) {
              resolver.write(path, (keyBuilder as dynamic)(snap));
            }

            break;
        }
      } else if (globalPersistorSettings is PersistorSettings) {
        encrypted = globalPersistorSettings.encrypted;

        switch (globalPersistorSettings) {
          case PersistorSettings(key: PersistorBuilderKey keyBuilder):
            final snap = doc.get();
            final path = doc.path;

            if (snap != null) {
              resolver.write(path, (keyBuilder as dynamic)(snap));
            }
            break;
          default:
            break;
        }
      }

      persistDocs.add(
        PersistenceDocument(
          path: doc.path,
          data: doc.getSerialized(),
          encrypted: encrypted,
        ),
      );
    }
  }
}
