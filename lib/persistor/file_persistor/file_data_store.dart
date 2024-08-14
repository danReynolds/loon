import 'dart:async';
import 'dart:convert';
import 'dart:io';
import 'package:encrypt/encrypt.dart';
import 'package:loon/loon.dart';
import 'package:loon/persistor/file_persistor/file_persistor_worker.dart';
import 'package:path/path.dart' as path;

final fileRegex = RegExp(
  r'^(?!__localResolver__)(\w+?)(?:.encrypted)?\.json$',
);

class DualFileDataStore {
  late final FileDataStore _plaintextStore;
  late final EncryptedFileDataStore _encryptedStore;

  final String name;

  DualFileDataStore({
    required this.name,
    required Directory directory,
    required Encrypter encrypter,
    bool isHydrated = false,
  }) {
    _plaintextStore = FileDataStore(
      directory: directory,
      name: name,
      isHydrated: isHydrated,
    );
    _encryptedStore = EncryptedFileDataStore(
      name: name,
      encrypter: encrypter,
      directory: directory,
      isHydrated: isHydrated,
    );
  }

  @override
  bool operator ==(Object other) {
    if (identical(this, other)) {
      return true;
    }
    if (other is DualFileDataStore) {
      return other.name == name;
    }
    return false;
  }

  @override
  int get hashCode => Object.hashAll([name]);

  bool hasValue(String resolverPath, String path) {
    return _plaintextStore.hasValue(resolverPath, path) ||
        _encryptedStore.hasValue(resolverPath, path);
  }

  void writePath(
    String? resolverPath,
    String path,
    dynamic value,
    bool encrypted,
  ) async {
    resolverPath ??= '';

    // If the document was previously not encrypted and now is, then it should be removed
    // from the plaintext store and added to the encrypted one and vice-versa.
    if (encrypted) {
      if (_plaintextStore.hasValue(resolverPath, path)) {
        _plaintextStore.shallowDelete(resolverPath, path);
      }
      _encryptedStore.writePath(resolverPath, path, value);
    } else {
      if (_encryptedStore.hasValue(resolverPath, path)) {
        _encryptedStore.shallowDelete(resolverPath, path);
      }
      _plaintextStore.writePath(resolverPath, path, value);
    }
  }

  /// Deletes the path recursively from all resolver stores.
  void recursiveDelete(String path) {
    _plaintextStore.recursiveDelete(path);
    _encryptedStore.recursiveDelete(path);
  }

  /// Deletes the path shallowly from the given resolver path store.
  void shallowDelete(String resolverPath, String path) {
    _plaintextStore.shallowDelete(resolverPath, path);
    _encryptedStore.shallowDelete(resolverPath, path);
  }

  Future<void> hydrate() async {
    if (isHydrated) {
      return;
    }

    await Future.wait([_plaintextStore.hydrate(), _encryptedStore.hydrate()]);
  }

  Future<void> sync() async {
    await Future.wait([_plaintextStore.sync(), _encryptedStore.sync()]);
  }

  Future<void> delete() async {
    await Future.wait([_plaintextStore.delete(), _encryptedStore.delete()]);
  }

  bool get isHydrated {
    return _plaintextStore.isHydrated && _encryptedStore.isHydrated;
  }

  bool get isEmpty {
    return isHydrated && _plaintextStore.isEmpty && _encryptedStore.isEmpty;
  }

  bool get isDirty {
    return _plaintextStore.isDirty || _encryptedStore.isDirty;
  }

  /// Grafts the data under resolver path [otherResolverPath] from the [other] data store
  /// into this data store at resolver path [resolverPath].
  void graft(
    String resolverPath,
    String otherResolverPath,
    String? dataPath,
    DualFileDataStore other,
  ) async {
    _plaintextStore.graft(
      resolverPath,
      otherResolverPath,
      dataPath,
      other._plaintextStore,
    );
    _encryptedStore.graft(
      resolverPath,
      otherResolverPath,
      dataPath,
      other._encryptedStore,
    );
  }

  static DualFileDataStore parse(
    File file, {
    required Encrypter encrypter,
    required Directory directory,
  }) {
    final match = fileRegex.firstMatch(path.basename(file.path));
    final name = match!.group(1)!;

    return DualFileDataStore(
      name: name,
      directory: directory,
      encrypter: encrypter,
    );
  }

  /// Returns a map of all values in the data store under the given path.
  Map<String, dynamic> extract([String path = '']) {
    return {
      ..._plaintextStore.extract(path),
      ..._encryptedStore.extract(path),
    };
  }

  Map inspect() {
    return {
      "plaintext": _plaintextStore.inspect(),
      "encrypted": _encryptedStore.inspect(),
    };
  }
}

class FileDataStore {
  /// The file associated with the data store.
  late final File _file;

  /// The file data store indexes documents into a local resolver by resolver path,
  /// then a value store by document path. This is done to enable efficient access and modification
  /// of data by resolver path and path.
  final _localResolver = ValueStore<ValueStore>();

  /// The name of the file data store.
  final String name;

  /// The file data store name suffix.
  final String suffix;

  /// Whether the plaintext store has pending changes that should be persisted.
  bool isDirty = false;

  /// Whether the file data store has been hydrated yet from its persisted file.
  bool isHydrated;

  late final Logger _logger;

  /// The name of the default data store key.
  static const defaultKey = '__store__';

  FileDataStore({
    required this.name,
    required Directory directory,
    this.isHydrated = false,
    this.suffix = '',
  }) {
    final fileName = "$name$suffix";

    _logger = Logger(
      'FileDataStore:$name',
      output: FilePersistorWorker.logger.log,
    );
    _file = File("${directory.path}/$fileName.json");
  }

  Future<String?> _readFile() {
    return _logger.measure(
      "Read file",
      () async {
        if (await _file.exists()) {
          return _file.readAsString();
        }

        return null;
      },
    );
  }

  Future<void> _writeFile(String value) {
    return _logger.measure(
      'Write file',
      () => _file.writeAsString(value),
    );
  }

  void _assertHydrated() {
    assert(isHydrated, 'FileDataStore data accessed before hydrated.');
  }

  bool hasValue(String resolverPath, String path) {
    _assertHydrated();

    return _localResolver.get(resolverPath)?.hasValue(path) ?? false;
  }

  /// Returns a map of the subset of documents in the store under the given path.
  /// Data for the given path can exist in two different places:
  /// 1. It necessarily exists in all of the value stores resolved under the given path.
  /// 2. It *could* exist in any of the parent value stores of the given path, such as in the example of the "users"
  ///    path containing data for path users__1, users__1__friends__1, etc.
  Map<String, dynamic> extract([String path = '']) {
    _assertHydrated();

    Map<String, dynamic> data = {};

    final parentStores = _localResolver.getPathValues(path);
    final childStores = _localResolver.extractUniqueValues(path);

    for (final store in parentStores) {
      data.addAll(store.extract(path));
    }
    for (final store in childStores) {
      data.addAll(store.extract(path));
    }

    return data;
  }

  void writePath(String resolverPath, String path, dynamic value) async {
    _assertHydrated();

    ValueStore? store = _localResolver.get(resolverPath) ??
        _localResolver.write(resolverPath, ValueStore());
    store.write(path, value);

    isDirty = true;
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
    _assertHydrated();

    // 1. Delete the given path from the resolver, evicting all documents under that path that were stored in
    //    resolver paths at or under that path.
    _localResolver.delete(path);

    // 2. Evict the given path from any parent stores above the given path.
    final stores = _localResolver.getPathValues(path);
    for (final store in stores) {
      // Data under the given path can only exist in one parent path store at a time, so deletion can exit early
      // once a parent path is found.
      if (store.hasPath(path)) {
        store.delete(path);
        break;
      }
    }
  }

  /// Shallowly deletes the given document path from the given resolver path store.
  void shallowDelete(String resolverPath, String path) {
    final resolver = _localResolver.get(resolverPath);

    if (resolver == null) {
      return;
    }

    resolver.delete(path, recursive: false);
    if (resolver.isEmpty) {
      _localResolver.delete(resolverPath, recursive: false);
    }
  }

  Future<void> hydrate() async {
    if (isHydrated) {
      return;
    }

    if (!(await _file.exists())) {
      isHydrated = true;
      return;
    }

    try {
      await _logger.measure(
        'Hydrate',
        () async {
          final encodedStore = await _readFile();
          if (encodedStore != null) {
            final Map json = jsonDecode(encodedStore);

            for (final entry in json.entries) {
              final resolverPath = entry.key;
              final valueStore = ValueStore.fromJson(entry.value);
              _localResolver.write(resolverPath, valueStore);
            }
          }
          isHydrated = true;
        },
      );
    } catch (e) {
      _logger.log('Corrupt file data store $name');
      rethrow;
    }
  }

  Future<void> sync() async {
    _assertHydrated();

    if (isEmpty) {
      await delete();
    } else if (isDirty) {
      await persist();
    }
  }

  Future<void> persist() async {
    _assertHydrated();

    if (isEmpty) {
      _logger.log('Empty store persist');
      return;
    }

    if (!isDirty) {
      _logger.log('Clean store persist');
      return;
    }

    await _logger.measure(
      'Persist',
      () => _writeFile(jsonEncode(inspect())),
    );

    isDirty = false;
  }

  Future<void> delete() async {
    if (await _file.exists()) {
      await _file.delete();
    }
  }

  bool get isEmpty {
    return _localResolver.isEmpty;
  }

  /// Grafts the data in the given [other] data store under resolver path [otherResolverPath] and data path [dataPath]
  /// into this data store under resolver path [resolverPath] at data path [dataPath].
  void graft(
    String resolverPath,
    String otherResolverPath,
    String? dataPath,
    FileDataStore other,
  ) {
    _assertHydrated();

    final store = _localResolver.get(resolverPath) ?? ValueStore<String>();
    final otherStore = other._localResolver.get(otherResolverPath);

    if (otherStore == null) {
      return;
    }

    store.graft(otherStore, dataPath);

    // After the graft, both affected data stores must be marked as dirty.
    isDirty = true;
    other.isDirty = true;
  }

  Map inspect() {
    return _localResolver.extract();
  }
}

class EncryptedFileDataStore extends FileDataStore {
  final Encrypter encrypter;

  EncryptedFileDataStore({
    required super.name,
    required super.directory,
    required this.encrypter,
    super.isHydrated = false,
  }) : super(suffix: '.encrypted');

  String _encrypt(String plainText) {
    final iv = IV.fromSecureRandom(16);
    return iv.base64 + encrypter.encrypt(plainText, iv: iv).base64;
  }

  String _decrypt(String encrypted) {
    final iv = IV.fromBase64(encrypted.substring(0, 24));
    return encrypter.decrypt64(
      encrypted.substring(24),
      iv: iv,
    );
  }

  @override
  _readFile() async {
    final encodedStore = await super._readFile();

    if (encodedStore != null) {
      return _decrypt(encodedStore);
    }

    return null;
  }

  @override
  _writeFile(String value) async {
    return super._writeFile(_encrypt(value));
  }
}

class FileDataStoreResolver {
  late final File _file;

  var _store = ValueRefStore<String>();

  static const name = '__localResolver__';

  late final Logger _logger;

  bool isDirty = false;

  FileDataStoreResolver({
    required Directory directory,
  }) {
    _logger = Logger(
      'FileDataStoreResolver',
      output: FilePersistorWorker.logger.log,
    );
    _file = File("${directory.path}/$name.json");

    // Initialize the store with a root key of the default file data store.
    _store.write('', FileDataStore.defaultKey);
  }

  void writePath(String path, dynamic value) {
    if (_store.get(path) != value) {
      _store.write(path, value);
      isDirty = true;
    }
  }

  void deletePath(
    String path, {
    bool recursive = true,
  }) {
    if (_store.hasValue(path) || recursive && _store.hasPath(path)) {
      _store.delete(path, recursive: recursive);
      isDirty = true;
    }
  }

  Map<String, int>? getRefs(String path) {
    return _store.getRefs(path);
  }

  (String, String)? getNearest(String path) {
    return _store.getNearest(path);
  }

  String? get(String path) {
    return _store.get(path);
  }

  Future<void> hydrate() async {
    try {
      await _logger.measure(
        'Hydrate',
        () async {
          if (await (_file.exists())) {
            final fileStr = await _file.readAsString();
            _store = ValueRefStore<String>(jsonDecode(fileStr));
          }
        },
      );
    } catch (e) {
      // If hydration fails for an existing file, then this file data store is corrupt
      // and should be removed from the file data store index.
      _logger.log('Corrupt file.');
      rethrow;
    }
  }

  Future<void> persist() async {
    if (_store.isEmpty) {
      _logger.log('Empty persist');
      return;
    }

    await _logger.measure(
      'Persist',
      () => _file.writeAsString(jsonEncode(_store.inspect())),
    );
  }

  Future<void> delete() async {
    await _logger.measure(
      'Delete',
      () async {
        if (await _file.exists()) {
          await _file.delete();
        }
        _store.clear();
      },
    );
  }

  Future<void> sync() async {
    if (_store.isEmpty) {
      await delete();
    } else if (isDirty) {
      await persist();
    }
  }
}
