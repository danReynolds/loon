import 'package:encrypt/encrypt.dart';
import 'package:loon/loon.dart';

class DataStoreValueStore extends ValueStore<ValueStore> {
  /// Whether the store has pending changes that should be persisted.
  bool isDirty = false;

  final bool encrypted;

  static const _plaintextKey = 'plaintext';
  static const _encryptedKey = 'encrypted';

  String get key {
    return encrypted ? _encryptedKey : _plaintextKey;
  }

  DataStoreValueStore(
    super.store, {
    required this.encrypted,
  });

  @override
  write(String path, ValueStore value) {
    isDirty = true;
    return super.write(path, value);
  }

  @override
  void delete(String path, {bool recursive = true}) {
    isDirty = true;
    super.delete(path, recursive: recursive);
  }

  @override
  void graft(ValueStore<ValueStore> other, [String? path = '']) {
    isDirty = true;
    super.graft(other, path);
  }
}

abstract class DataStore {
  /// A data store indexes documents in its store by the document path at which its persistence key is specified,
  /// then the full document path.
  final plaintextStore = DataStoreValueStore(null, encrypted: false);
  final encryptedStore = DataStoreValueStore(null, encrypted: true);

  /// The name of the file data store.
  final String name;

  final Encrypter encrypter;

  /// Whether the data store has been hydrated yet from its persisted file.
  bool isHydrated;

  DataStore(
    this.name, {
    required this.encrypter,
    this.isHydrated = false,
  });

  String encrypt(String plainText) {
    final iv = IV.fromSecureRandom(16);
    return iv.base64 + encrypter.encrypt(plainText, iv: iv).base64;
  }

  String decrypt(String encrypted) {
    final iv = IV.fromBase64(encrypted.substring(0, 24));
    return encrypter.decrypt64(
      encrypted.substring(24),
      iv: iv,
    );
  }

  bool get isDirty {
    return plaintextStore.isDirty || encryptedStore.isDirty;
  }

  bool hasValue(String resolverPath, String path) {
    return plaintextStore.get(resolverPath)?.hasValue(path) ??
        encryptedStore.get(resolverPath)?.hasValue(path) ??
        false;
  }

  bool hasPath(String resolverPath, String path) {
    return plaintextStore.get(resolverPath)?.hasPath(path) ??
        encryptedStore.get(resolverPath)?.hasPath(path) ??
        false;
  }

  dynamic get(String resolverPath, String path) {
    return plaintextStore.get(resolverPath)?.get(path) ??
        encryptedStore.get(resolverPath)?.get(path);
  }

  /// Returns a map of the subset of documents in the store under the given path.
  /// Data for the given path can exist in two different places:
  /// 1. It necessarily exists in all of the value stores resolved under the given path.
  /// 2. It *could* exist in any of the parent value stores of the given path, such as in the example of the "users"
  ///    path containing data for path users__1, users__1__friends__1, etc.
  Map<String, dynamic> extract([String path = '']) {
    Map<String, dynamic> data = {};

    for (final store in [plaintextStore, encryptedStore]) {
      final parentStores = store.extractParentPath(path).values;
      final childStores = store.extractValues(path);

      for (final parentStore in parentStores) {
        data.addAll(parentStore.extract(path));
      }
      for (final childStore in childStores) {
        data.addAll(childStore.extract(path));
      }
    }

    return data;
  }

  void writePath(
    String? resolverPath,
    String path,
    dynamic value,
    bool encrypted,
  ) async {
    resolverPath ??= '';
    ValueStore store;

    // If the document was previously not encrypted and now is, then it should be removed
    // from the plaintext store and added to the encrypted one and vice-versa.
    if (encrypted) {
      if (plaintextStore.get(resolverPath)?.hasValue(path) ?? false) {
        _shallowDelete(plaintextStore, resolverPath, path);
      }
      store = encryptedStore.get(resolverPath) ?? ValueStore();
    } else {
      if (encryptedStore.get(resolverPath)?.hasValue(path) ?? false) {
        _shallowDelete(encryptedStore, resolverPath, path);
      }
      store = plaintextStore.get(resolverPath) ?? ValueStore();
    }

    store.write(path, value);
  }

  void _recursiveDelete(DataStoreValueStore store, String path) {
    // 1. Delete the given path from the resolver, evicting all documents under that path that were stored in
    //    resolver paths at or under that path.
    if (store.hasPath(path)) {
      store.delete(path);
    }

    // 2. Evict the given path from any parent stores above the given path.
    final valueStores = store.extractParentPath(path);
    for (final entry in valueStores.entries) {
      final resolverPath = entry.key;
      final valueStore = entry.value;

      if (valueStore.hasPath(path)) {
        valueStore.delete(path);
        store.isDirty = true;

        if (valueStore.isEmpty) {
          store.delete(resolverPath, recursive: false);
        }

        // Data under the given path can only exist in one parent path store at a time, so deletion can exit early
        // once a parent path is found.
        break;
      }
    }
  }

  /// Deletes the given path from the data store recursively. Documents under the given path could be stored
  /// in one of two places:
  /// 1. In resolver paths under/equal to the given path.
  ///    These documents can easily be deleted by deleting all value stores under the document path in the resolver.
  /// 2. In a resolver path that is a parent path of the given path.
  ///    Ex. When deleting path users__1, all user documents might be stored in resolver path "users", or if no
  ///        custom persistence key has been specified anywhere along the path, then in the default store.
  ///
  ///    Therefore to delete the remaining documents under the given path, each value store in the resolver above the given path is visited
  ///    and has the given path evicted from its store.
  void recursiveDelete(String path) async {
    _recursiveDelete(plaintextStore, path);
    _recursiveDelete(encryptedStore, path);
  }

  void _shallowDelete(
    DataStoreValueStore store,
    String resolverPath,
    String path,
  ) {
    final dataStore = store.get(resolverPath);

    if (dataStore == null) {
      return;
    }

    if (!dataStore.hasValue(path)) {
      return;
    }

    dataStore.delete(path, recursive: false);

    if (dataStore.isEmpty) {
      store.delete(resolverPath, recursive: false);
    }
  }

  /// Shallowly deletes the given document path from the given resolver path store.
  void shallowDelete(String resolverPath, String path) {
    _shallowDelete(plaintextStore, resolverPath, path);
    _shallowDelete(encryptedStore, resolverPath, path);
  }

  bool get isEmpty {
    return plaintextStore.isEmpty && encryptedStore.isEmpty;
  }

  void _graft(
    DataStoreValueStore store,
    DataStoreValueStore otherStore,
    String resolverPath,
    String otherResolverPath,
    String? dataPath,
  ) {
    final otherValueStore = otherStore.get(otherResolverPath);
    if (otherValueStore == null) {
      return;
    }

    final valueStore =
        store.get(resolverPath) ?? store.write(resolverPath, ValueStore());
    valueStore.graft(otherStore, dataPath);

    if (otherStore.isEmpty) {
      otherStore.delete(otherResolverPath, recursive: false);
    }
  }

  /// Grafts the data in the given [other] data store under resolver path [otherResolverPath] and data path [dataPath]
  /// into this data store under resolver path [resolverPath] at data path [dataPath].
  void graft(
    String resolverPath,
    String otherResolverPath,
    String? dataPath,
    DataStore other,
  ) {
    _graft(
      plaintextStore,
      other.plaintextStore,
      resolverPath,
      otherResolverPath,
      dataPath,
    );
    _graft(
      encryptedStore,
      other.encryptedStore,
      resolverPath,
      otherResolverPath,
      dataPath,
    );
  }

  Map inspect() {
    return {
      "plaintext": plaintextStore.inspect(),
      "encrypted": encryptedStore.inspect(),
    };
  }

  Future<void> sync() async {
    if (isEmpty) {
      await delete();
    } else if (isDirty) {
      await persist();
    }
  }

  /// APIs to be implemented by each data store type.

  Future<void> hydrate();

  Future<void> persist();

  Future<void> delete();
}
