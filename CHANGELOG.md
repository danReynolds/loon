## 6.0.0

* Re-evaluate documents touched by a dependency change or `Document.rebroadcast()` in queries the way modified documents are, so a touched document can enter, leave or move within a query's results. Previously a query only re-emitted touched documents that were already in its results.
* Touch the dependents of every document under a deleted document or collection, including documents in nested subcollections.
* Remove deleted documents from the dependency graph eagerly, including documents in nested subcollections.
* Snapshot builder-owned dependency sets so reusing a mutable set cannot leave stale reverse dependencies.
* Make rebroadcasting a missing document do nothing.
* Speed up the value stores' reads, writes and deletes, and reduce document allocation and path lookup overhead.
* Fix a data store keeping empty entries after documents move out of it, such as when their persistence key changes, which kept an emptied data store from being deleted.
* [Breaking] Compare observable documents by path like plain documents, so an `ObservableDocument` equals other handles to the same document. Active observers are still tracked by identity.
* [Breaking] Store dependencies only for documents that have some, so `Document.dependencies()` returns `null` instead of an empty set when the dependencies builder returns one.
* [Breaking] Remove `PathRefStore` and `ObservableDocument.inspect()`, remove `deps` and `docDeps` from `ObservableQuery.inspect()`, and key its `docSnaps` by document ID. Dependency state is available through `Document.dependencies()` and `Document.dependents()`.
* [Breaking] In `Loon.inspect()`, return dependency entries as objects whose `toJson()` produces `{doc, dependencies}` using document paths, return `dependentsStore` as a path tree, and remove `dependencyCache`.
* [Breaking] Stop exporting `ValueStore` and `ValueRefStore`, which are internal to Loon.

## 5.6.1

* Update `flutter_secure_storage` to v10.
* Update web conditional import from `dart.library.html` to `dart.library.js_interop`.
* Remove temporary `flutter_secure_storage_web` dependency override for WASM support.

> **Note:** `flutter_secure_storage` v10 defaults to `useDataProtectionKeyChain: true` on macOS, which requires the `com.apple.security.keychain-access-groups` entitlement. See the [flutter_secure_storage migration guide](https://pub.dev/packages/flutter_secure_storage) for details.

## 5.6.0

* Add support for document ID generation a la Firestore.

## 5.5.0

* Core API audit/cleanup.

## 5.4.0

* Add [TransactionWriter] API for writing multiple updates together and rolling back if they fail.

## 5.3.0

* Add support for rebroadcasting from a [Document] and rebuilding a document's dependencies.
* Fixes bug in [PathRefStore.has] when traversing nested paths.

## 5.2.3

* Small bugfixes.

## 5.2.2

* Fix bug where deletion of non-existent documents was not deleting nested path documents.

## 5.2.1

* Update document modify API to support nullable return values.

## 5.2.0

* Refactor encrypter initialization.

## 5.1.2

* Fix bug in IndexedDB persistence.

## 5.1.1

* Fix bug with file data store clear.
* Refactor stubs

## 5.1.0

* Creates generic persistor worker isolate interface.
* Move SQLite operations to a worker isolate using new interface.
* Refactor logging for global enable/disable support.

## 5.0.0

* Adds web persistence support using the IndexedDBPersistor.
* Adds a SqlitePersistor for native platforms.

## 4.0.1

* Bugfix for default file data store instantiation.

## 4.0.0

* Rewrites file persistence.
* Fixes some edge case bugs with file persistence key resolution and improves subtree resolution performance.
* Decreases the isolate persistence payload through the use of a local resolver when persisting documents, enabling a smaller isolate message payload that decreases
  copy-time on the main isolate.

## 3.2.0

* Adds support for persisting serializable documents (primitives or custom classes with toJson support)
  using FilePersistor without specifying serializer.
* Fixes bug with ObservableDocument dependency updates.

## 3.1.0

* Updates to FilePersistor synchronization.

## 3.0.0

* Refactors dependency behavior into the dependency manager and de-dupes dependency references to improve performance.
* Moves base persistor batch/throttle behavior to the persist manager and updates persistence delays to be done at the task duration level in the manager and at the throttle duration in the file persistor implementation.
* Adds a caching layer to accessing observable values via get() ahead of a broadcast.

## 2.0.1

* Fix bug for deletion of documents with a document-level persistence key. 

## 2.0.0

* Rearchitecture of core implementation.

* [Breaking] Default behavior of deleting a document/collection is to recursively delete all nested data.
* `FilePersistor` changes:
    * [Breaking] Change from `getPersistenceKey` to `FilePersistor.key` and `FilePersistor.keyBuilder`.
    * [Breaking] Changed the default data store location from `loon.json` to `__store__.json`.
    * [Feature] Added ability to specify the collections/documents to hydrate when calling `Loon.hydrate()`.

## 1.2.0

* Fixed a bug where `clearAll` wasn't broadcasting to observers.
* Simplified logic of deleting collections recursively and broadcasting to observers.

## 1.1.0

* More fixes and improvements.

## 1.0.1

* Fixes propagation of the dependenciesBuilder field.

## 1.0.0

* Use of isolates for background persistence processing.
* Data dependency support with the `dependenciesBuilder` API.
* More architecture and performance improvements.

## 0.0.5

* More performance optimizations.

## 0.0.4

* Migrate `streamChanges` to a more useful, meta change API.

## 0.0.3

* Small fixes from more testing.

## 0.0.2

* Add support for global docs.

## 0.0.1

* Initial release.
