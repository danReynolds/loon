import 'dart:async';
import 'dart:convert';
import 'dart:io';
import 'package:encrypt/encrypt.dart';
import 'package:loon/loon.dart';
import 'package:loon/persistor/file_persistor/file_persistor_worker.dart';
import 'package:path/path.dart' as path;

final fileRegex = RegExp(
  r'^(?!__resolver__)(\w+?)(?:.encrypted)?\.json$',
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
    // If the document was previously not encrypted and now is, then it should be removed
    // from the plaintext store and added to the encrypted one and vice-versa.
    if (encrypted) {
      if (_plaintextStore.hasValue(resolverPath, path)) {
        _plaintextStore.deletePath(resolverPath, path, recursive: false);
      }
      _encryptedStore.writePath(resolverPath, path, value);
    } else {
      if (_encryptedStore.hasValue(resolverPath, path)) {
        _encryptedStore.deletePath(resolverPath, path, recursive: false);
      }
      _plaintextStore.writePath(resolverPath, path, value);
    }
  }

  void deletePath(
    String? resolverPath,
    String path, {
    bool recursive = true,
  }) async {
    _plaintextStore.deletePath(resolverPath, path, recursive: recursive);
    _encryptedStore.deletePath(resolverPath, path, recursive: recursive);
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
    String? resolverPath,
    String? otherResolverPath,
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

  /// Returns a map of values in the data store indexed by store path under the given resolver path.
  Map<String, dynamic> extractValuesForResolver(
    String resolverPath, [
    String path = '',
  ]) {
    return {
      ..._plaintextStore.extractValuesForResolver(resolverPath, path),
      ..._encryptedStore.extractValuesForResolver(resolverPath, path),
    };
  }

  /// Returns a map of all values in the data store indexed by resolver path and store path.
  Map<String?, Map<String, dynamic>> extractValuesByResolver([
    String path = '',
  ]) {
    return {
      ..._plaintextStore.extractValuesByResolver(path),
      ..._encryptedStore.extractValuesByResolver(path),
    };
  }

  /// Returns a map of all values in the data store indexed by store path.
  Map<String, dynamic> extractValues([
    String path = '',
  ]) {
    return {
      ..._plaintextStore.extractValues(path),
      ..._encryptedStore.extractValues(path),
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

  /// Documents are stored in a file data store by their resolver path, followed by their document path.
  final Map<String?, ValueStore> _resolver = {};

  /// The name of the file data store.
  final String name;

  /// The file data store name suffix.
  final String suffix;

  /// Whether the plaintext store has pending changes that should be persisted.
  bool isDirty = false;

  /// Whether the file data store has been hydrated yet from its persisted file.
  bool isHydrated;

  // Completer used to await hydration of the data store.
  Completer<void>? _hydrationCompleter;

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

  bool hasValue(String? resolverPath, String path) {
    _assertHydrated();

    return _resolver[resolverPath]?.hasValue(path) ?? false;
  }

  void writePath(
    String? resolverPath,
    String path,
    dynamic value,
  ) async {
    _assertHydrated();

    final store = _resolver[resolverPath] ??= ValueStore<String>();
    store.write(path, value);

    isDirty = true;
  }

  void deletePath(
    String? resolverPath,
    String path, {
    bool recursive = true,
  }) async {
    _assertHydrated();

    final store = _resolver[resolverPath];
    if (store == null) {
      return;
    }

    if (store.hasValue(path) || recursive && store.hasPath(path)) {
      store.delete(path, recursive: recursive);
      isDirty = true;
    }
  }

  Future<void> hydrate() async {
    if (isHydrated) {
      return;
    }

    if (_hydrationCompleter != null) {
      return _hydrationCompleter!.future;
    }

    if (!(await _file.exists())) {
      isHydrated = true;
      return;
    }

    try {
      await _logger.measure(
        'Hydrate',
        () async {
          _hydrationCompleter = Completer();
          final encodedStore = await _readFile();
          if (encodedStore != null) {
            final Map stores = jsonDecode(encodedStore);
            for (final entry in stores.entries) {
              _resolver[entry.key] = ValueStore.fromJson(entry.value);
            }
          }
          _hydrationCompleter!.complete();
          isHydrated = true;
        },
      );
    } catch (e) {
      _hydrationCompleter!.completeError(e);
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
    return _resolver.isEmpty;
  }

  /// Grafts the data at the given [path] in the other [FileDataStore] onto
  /// this data store at that path.
  void graft(
    String? resolverPath,
    String? otherResolverPath,
    String? dataPath,
    FileDataStore other,
  ) {
    _assertHydrated();

    final store = _resolver[resolverPath] ?? ValueStore<String>();
    final otherStore = other._resolver[otherResolverPath]!;

    store.graft(otherStore, dataPath);

    // After the graft, both affected data stores must be marked as dirty.
    isDirty = true;
    other.isDirty = true;
  }

  /// Returns a map of values in the data store indexed by store path under the given resolver path.
  Map<String, dynamic> extractValuesForResolver(
    String resolverPath, [
    String path = '',
  ]) {
    _assertHydrated();

    return _resolver[resolverPath]?.extractValues(path) ?? {};
  }

  /// Returns a map of all values in the data store indexed by resolver path and store path.
  Map<String?, Map<String, dynamic>> extractValuesByResolver([
    String path = '',
  ]) {
    _assertHydrated();

    return _resolver.entries.fold(
      {},
      (acc, entry) {
        acc[entry.key] = entry.value.extractValues();
        return acc;
      },
    );
  }

  /// Returns a map of all values in the data store indexed by store path.
  Map<String, dynamic> extractValues([String path = '']) {
    _assertHydrated();

    return _resolver.entries.fold(
      {},
      (acc, entry) {
        acc.addAll(entry.value.extractValues());
        return acc;
      },
    );
  }

  Map inspect() {
    return _resolver.entries.fold(
      {},
      (acc, entry) {
        acc[entry.key] = entry.value.inspect();
        return acc;
      },
    );
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

  var _store = ValueStore<String>();

  static const name = '__resolver__';

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

  Map<String, String> extractValues([String path = '']) {
    return _store.extractValues(path);
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
            _store = ValueStore(jsonDecode(fileStr));
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
