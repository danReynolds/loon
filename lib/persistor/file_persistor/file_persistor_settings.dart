import 'package:loon/loon.dart';

/// By default, documents are persisted to a file grouped by their top-level collection. For example,
/// a document with path users__1 and users__1__posts__1 are both persisted to a users.json file, while
/// messages__1 would be persisted to messages.json.
///
/// To customize this behavior, a custom [FilePersistorKey] can be specified.
///
/// Ex. 1: Static keys.
/// ```dart
/// Loon.collection(
///   'users',
///   settings: FilePersistorSettings(
///     key: FilePersistor.key('custom'),
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
///   settings: FilePersistorSettings(
///     key: FilePersistor.keyBuilder((snap) {
///       return "birds_${snap.data.species}";
///     }),
///   ),
/// );
/// ```
/// Documents from the same collection can be given different persistence keys using [FilePersistor.keyBuilder].
/// This allows you to customize persistence on a per-document level, supporting scenarios like sharding of large collections.

typedef FilePersistorKeyBuilder<T> = String Function(DocumentSnapshot<T> snap);

class FilePersistorSettings<T> extends PersistorSettings {
  /// The persistence key to use for this collection. The key corresponds to the name of the file
  /// that the collection's data and all of the data of its subcollections (that don't specify their own custom key)
  /// is stored in.
  ///
  /// Ex. Customizing a collection's persistence key:
  /// ```dart
  /// Loon.collection(
  ///   'users',
  ///   settings: FilePersistorSettings(
  ///     key: FilePersistor.key('custom_users_key'),
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
  ///   settings: FilePersistorSettings(
  ///     key: FilePersistor.keyBuilder((snap) {
  ///       if (snap.data.role == 'admin') {
  ///         return 'admins';
  ///       }
  ///       return 'users';
  ///     }),
  ///   ),
  /// );
  /// ```
  final FilePersistorKeyBuilder<T>? keyBuilder;

  final String? key;

  /// Whether encryption is enabled globally for all collections in the store.
  final bool encrypted;

  const FilePersistorSettings({
    this.key,
    this.keyBuilder,
    this.encrypted = false,
    super.enabled = true,
  });
}
