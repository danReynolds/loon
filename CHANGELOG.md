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
