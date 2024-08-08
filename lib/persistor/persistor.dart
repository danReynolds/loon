part of loon;

class PersistorSettings {
  final bool enabled;

  const PersistorSettings({
    this.enabled = true,
  });
}

class DocumentPersistorSettings extends PersistorSettings {
  final Document doc;
  final PersistorSettings settings;

  const DocumentPersistorSettings({
    required this.settings,
    required this.doc,
  });

  @override
  get enabled {
    return settings.enabled;
  }
}

/// Abstract persistor that implements the base persistence batching, de-duping and locking of
/// persistence operations. Exposes the public persistence APIs for persistence implementations to implement.
/// See [FilePersistor] as an example implementation.
abstract class Persistor {
  final PersistorSettings settings;
  final void Function(Set<Document> batch)? onPersist;
  final void Function(Set<Collection> collections)? onClear;
  final void Function()? onClearAll;
  final void Function(Json data)? onHydrate;

  Persistor({
    this.onPersist,
    this.onClear,
    this.onClearAll,
    this.onHydrate,
    this.settings = const PersistorSettings(),
  });

  ///
  /// Public APIs to be implemented by any [Persistor] extension like [FilePersistor].
  ///

  /// Initialization function called when the persistor is instantiated to execute and setup work.
  Future<void> init();

  /// Persist function called with the bath of documents that have changed (including been deleted) within the last throttle window
  /// specified by the [Persistor.persistenceThrottle] duration.
  Future<void> persist(List<Document> docs);

  /// Hydration function called to read data from persistence. If no entities are specified,
  /// then it hydrations all persisted data. if entities are specified, it hydrates only the data from
  /// the paths under those entities.
  Future<Json> hydrate([List<StoreReference>? refs]);

  /// Clear function used to clear all documents under the given collections.
  Future<void> clear(List<Collection> collections);

  /// Clears all documents and removes all persisted data.
  Future<void> clearAll();
}
