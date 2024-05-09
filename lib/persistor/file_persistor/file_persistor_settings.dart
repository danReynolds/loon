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

enum FilePersistorKeyTypes {
  collection,
  document,
}

class FilePersistorKey<T> {
  final String value;
  final FilePersistorKeyTypes type;

  FilePersistorKey(this.value, this.type);
}

abstract class FilePersistorKeyBuilder<T> {}

class FilePersistorCollectionKeyBuilder<T> extends FilePersistorKeyBuilder<T> {
  final String value;

  FilePersistorCollectionKeyBuilder(
    this.value,
  );

  build() {
    return FilePersistorKey<T>(value, FilePersistorKeyTypes.collection);
  }
}

class FilePersistorDocumentKeyBuilder<T> extends FilePersistorKeyBuilder<T> {
  final String Function(DocumentSnapshot<T> snap) builder;

  FilePersistorDocumentKeyBuilder(this.builder);

  FilePersistorKey<T> build(DocumentSnapshot<T> snap) {
    return FilePersistorKey<T>(builder(snap), FilePersistorKeyTypes.document);
  }
}

class FilePersistorSettings<T> extends PersistorSettings<T> {
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
  final FilePersistorKeyBuilder<T>? key;

  /// Whether encryption is enabled globally for all collections in the store.
  final bool encrypted;

  const FilePersistorSettings({
    this.key,
    this.encrypted = false,
    super.enabled = true,
    super.persistenceThrottle = const Duration(milliseconds: 100),
  });

  FilePersistorSettings<T> copyWith({
    FilePersistorKeyBuilder<T>? key,
    bool? encrypted,
    bool? enabled,
    Duration? persistenceThrottle,
  }) {
    return FilePersistorSettings<T>(
      key: key ?? this.key,
      encrypted: encrypted ?? this.encrypted,
      enabled: enabled ?? this.enabled,
      persistenceThrottle: persistenceThrottle ?? this.persistenceThrottle,
    );
  }
}
