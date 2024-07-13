part of loon;

/// The data returned on hydration from the hydration layer as a map of document
/// paths to document data.
typedef HydrationData = Map<String, Json>;

class PersistorSettings<T> {
  final bool enabled;

  const PersistorSettings({
    this.enabled = true,
  });
}

/// Abstract persistor that implements the base persistence batching, de-duping and locking of
/// persistence operations. Exposes the public persistence APIs for persistence implementations to implement.
/// See [FilePersistor] as an example implementation.
abstract class Persistor {
  final PersistorSettings settings;
  final void Function(Set<Document> batch)? onPersist;
  final void Function(Set<Collection> collections)? onClear;
  final void Function()? onClearAll;
  final void Function(HydrationData data)? onHydrate;

  /// The throttle for batching persisted documents. All documents updated within the throttle
  /// duration are batched together into a single persist operation.
  final Duration persistenceThrottle;

  Persistor({
    this.settings = const PersistorSettings(),
    this.persistenceThrottle = const Duration(milliseconds: 100),
    this.onPersist,
    this.onClear,
    this.onClearAll,
    this.onHydrate,
  });

  ///
  /// Public APIs to be implemented by any [Persistor] extension like [FilePersistor].
  ///

  /// Initialization function called when the persistor is instantiated to execute and setup work.
  Future<void> init();

  /// Persist function called with the bath of documents that have changed (including been deleted) within the last throttle window
  /// specified by the [Persistor.persistenceThrottle] duration.
  Future<void> persist(Set<Document> docs);

  /// Hydration function called to read data from persistence. If no entities are specified,
  /// then it hydrations all persisted data. if entities are specified, it hydrates only the data from
  /// the paths under those entities.
  Future<HydrationData> hydrate([Set<StoreReference>? refs]);

  /// Clear function used to clear all documents under the given collections.
  Future<void> clear(Set<Collection> collections);

  /// Clears all documents and removes all persisted data.
  Future<void> clearAll();
}
