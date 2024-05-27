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
