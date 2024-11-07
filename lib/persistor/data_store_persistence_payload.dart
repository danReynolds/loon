import 'package:loon/loon.dart';
import 'package:loon/persistor/persistence_document.dart';

/// Builds a persistence payload from a list of updated documents.
class DataStorePersistencePayload {
  /// A local persistence key resolver derived from the set of updated documents.
  late final ValueStore<String> resolver;

  /// The list of updated documents to persist.
  final List<PersistenceDocument> persistenceDocs = [];

  DataStorePersistencePayload(List<Document> docs) {
    // The updated persistence keys for documents are built into a local resolver
    // passed to the worker. This has two main benefits:
    // 1. It pre-computes the resolved persistence keys across the document updates, eliminating conflicts.
    //    Ex. If an update to users__1__friends__1 which resolves to persistence key "users" at resolver path "users"
    //        is followed by a subsequent update to users__1 that changes the persistence key at resolver path "users" to "other_users",
    //        then the previous update to users__1__friends__1 would have an inaccurate persistence key.

    //    Pre-computing the local resolver ensures that all documents can lookup accurate persistence keys.
    //    were not pre-computed in this way, then there could be conflicts between the changes documents make
    //
    // 2. It de-duplicates persistence keys. If there are many documents that all roll up
    //    to a given key, then the key is only specified once in the local resolver rather than
    //    being duplicated and sent independently with each document.
    resolver = ValueStore<String>();
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
        final settingsDoc = persistorSettings.doc;
        final docSettings = persistorSettings.settings;

        encrypted = docSettings.encrypted;

        switch (docSettings) {
          case PersistorSettings(key: PersistorValueKey key):
            String path;

            /// A value key is stored at the parent path of the document unless it is a document
            /// on the root collection via [Loon.doc], which should store keys under its own path.
            if (settingsDoc.parent != Collection.root.path) {
              path = settingsDoc.parent;
            } else {
              path = settingsDoc.path;
            }

            resolver.write(path, key.value);

            break;
          case PersistorSettings(key: PersistorBuilderKey keyBuilder):
            final snap = settingsDoc.get();
            final path = settingsDoc.path;

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

      persistenceDocs.add(
        PersistenceDocument(
          path: doc.path,
          data: doc.getSerialized(),
          encrypted: encrypted,
        ),
      );
    }
  }
}
