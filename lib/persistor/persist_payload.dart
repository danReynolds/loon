import 'package:loon/loon.dart';
import 'package:loon/persistor/persistence_document.dart';

///  Preprocesses the resolved persistence keys across the batch of documents, eliminating conflicts.
///
///  Ex. If an update to users__1__friends__1 which resolves to persistence key "users" at resolver path "users"
///      is followed by a subsequent update to users__1 that changes the persistence key at resolver path "users" to "other_users",
///      then the previous update to users__1__friends__1 would have an inaccurate persistence key.
///
///  By preprocessing the updates into a single resolver, it prevents staleness and also optimizes the payload size by not duplicating
///  the passing of keys.
class PersistPayload {
  /// A local persistence key resolver derived from the set of updated documents.
  final resolver = ValueStore<String>();

  /// The list of updated documents to persist.
  final List<PersistenceDocument> persistenceDocs = [];

  PersistPayload(List<Document> docs) {
    final globalPersistorSettings = Loon.persistorSettings;

    final defaultKey = switch (globalPersistorSettings) {
      PersistorSettings(key: PersistorValueKey key) => key,
      _ => Persistor.defaultKey,
    };
    resolver.write(ValueStore.root, defaultKey.value);

    for (final doc in docs) {
      final pathSettings = doc.persistorSettings;

      if (pathSettings != null) {
        switch (pathSettings) {
          case PathPersistorSettings(
              ref: final ref,
              key: PersistorValueKey key
            ):
            resolver.write(ref.path, key.value);
            break;
          case PathPersistorSettings(
              ref: Document doc,
              key: PersistorBuilderKey keyBuilder,
            ):
            final path = doc.path;
            final snap = doc.get();

            if (snap != null) {
              resolver.write(path, (keyBuilder as dynamic)(snap));
            }

            break;
        }
      } else if (globalPersistorSettings is PersistorSettings) {
        switch (globalPersistorSettings) {
          case PersistorSettings(key: PersistorBuilderKey keyBuilder):
            final path = doc.path;
            final snap = doc.get();

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
          encrypted: doc.encrypted,
        ),
      );
    }
  }
}
