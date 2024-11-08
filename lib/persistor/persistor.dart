part of loon;

/// By default, documents are persisted to a global data store grouped by their top-level collection. For example,
/// a document with path users__1 and users__1__posts__1 are both persisted to a users.json file, while
/// messages__1 would be persisted to messages.json.
///
/// To customize this behavior, a custom [PersistorKey] can be specified.
///
/// Ex. 1: Static keys.
/// ```dart
/// Loon.collection(
///   'users',
///   settings: PersistorSettings(
///     key: Persistor.key('custom'),
///   ),
/// );
/// ```
///
/// In this example, all documents of the 'users' collection will be stored using the custom persistence key
/// and placed in the `custom.json` file instead of the default `users.json` file for their collection.
///
/// Ex. 2: Dynamic keys.
/// ```dart
/// Loon.collection(
///   'birds',
///   settings: PersistorSettings(
///     key: Persistor.keyBuilder((snap) {
///       return "birds_${snap.data.species}";
///     }),
///   ),
/// );
/// ```
/// Documents from the same collection can be given different persistence keys using [Persistor.keyBuilder].
/// This allows you to customize persistence on a per-document level, supporting scenarios like sharding of large collections.

typedef PersistorKeyBuilder<T> = String Function(DocumentSnapshot<T> snap);

class PersistorKey {}

class PersistorValueKey extends PersistorKey {
  final String value;

  PersistorValueKey(this.value);
}

class PersistorBuilderKey<T> extends PersistorKey {
  final PersistorKeyBuilder<T> _builder;

  PersistorBuilderKey(this._builder);

  String call(DocumentSnapshot<T> snap) {
    return _builder(snap);
  }
}

class PersistorSettings<T> {
  /// The persistence key to use for this collection. The key corresponds to the name of the file
  /// that the collection's data and all of the data of its subcollections (that don't specify their own custom key)
  /// is stored in.
  ///
  /// Ex. Customizing a collection's persistence key:
  /// ```dart
  /// Loon.collection(
  ///   'users',
  ///   settings: PersistorSettings(
  ///     key: Persistor.key('custom_users_key'),
  ///   ),
  /// );
  /// ```
  ///
  /// Ex. Customizing a document's persistence key:
  ///
  /// If documents from the same collection should be distributed to multiple files, then a key builder can be used to
  /// vary the persistence key to use at the document-level based on its latest snapshot.
  /// ```dart
  /// Loon.collection(
  ///   'users',
  ///   settings: PersistorSettings(
  ///     key: Persistor.keyBuilder((snap) {
  ///       if (snap.data.role == 'admin') {
  ///         return 'admins';
  ///       }
  ///       return 'users';
  ///     }),
  ///   ),
  /// );
  /// ```

  final PersistorKey? key;

  /// Whether encryption is enabled globally for all collections in the store.
  final bool encrypted;

  /// Whether persistence is enabled.
  final bool enabled;

  const PersistorSettings({
    this.key,
    this.encrypted = false,
    this.enabled = true,
  });
}

class DocumentPersistorSettings extends PersistorSettings {
  /// The document at which the persistor settings was specified.
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
/// See [Persistor] as an example implementation.
abstract class Persistor {
  final PersistorSettings settings;
  final void Function(Set<Document> batch)? onPersist;
  final void Function(Set<Collection> collections)? onClear;
  final void Function()? onClearAll;
  final void Function(Json data)? onHydrate;
  final void Function()? onSync;

  /// The throttle for batching persisted documents. All documents updated within the throttle
  /// duration are batched together into a single persist operation.
  final Duration persistenceThrottle;

  Persistor({
    this.onPersist,
    this.onClear,
    this.onClearAll,
    this.onHydrate,
    this.onSync,
    this.settings = const PersistorSettings(),
    this.persistenceThrottle = const Duration(milliseconds: 100),
  });

  /// The name of the default [DataStore] key.
  static final PersistorValueKey defaultKey = Persistor.key('__store__');

  /// Selects the persistor to use based on the current platform. By default, this is the
  /// [FilePersistor] for non-web platforms and the [IndexedDBPersistor] for web.
  static Persistor current({
    void Function(Set<Document> batch)? onPersist,
    void Function(Set<Collection> collections)? onClear,
    void Function()? onClearAll,
    void Function(Json data)? onHydrate,
    void Function()? onSync,
    Duration persistenceThrottle = const Duration(milliseconds: 100),
    PersistorSettings settings = const PersistorSettings(),
  }) {
    return PlatformPersistor(
      onPersist: onPersist,
      onClear: onClear,
      onClearAll: onClearAll,
      onHydrate: onHydrate,
      settings: settings,
      persistenceThrottle: persistenceThrottle,
    );
  }

  static PersistorValueKey key<T>(String value) {
    return PersistorValueKey(value);
  }

  static PersistorBuilderKey keyBuilder<T>(
    String Function(DocumentSnapshot<T> snap) builder,
  ) {
    return PersistorBuilderKey<T>(builder);
  }

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
