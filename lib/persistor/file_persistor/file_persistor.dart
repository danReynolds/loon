import 'dart:async';
import 'dart:io';
import 'package:loon/loon.dart';
import 'package:loon/persistor/data_store.dart';
import 'package:loon/persistor/data_store_encrypter.dart';
import 'package:loon/persistor/data_store_manager.dart';
import 'package:loon/persistor/data_store_resolver.dart';
import 'package:loon/persistor/file_persistor/file_data_store_config.dart';
import 'package:path_provider/path_provider.dart';
import 'package:path/path.dart' as path;

/// A worker abstraction that creates a background worker isolate to process file persistence/hydration.
class FilePersistor extends Persistor {
  final Logger logger;
  final DataStoreEncrypter encrypter;

  late final DataStoreManager _manager;

  final _fileRegex = RegExp(r'^(?!__resolver__)(\w+?)(?:.encrypted)?\.json$');

  FilePersistor({
    super.onPersist,
    super.onClear,
    super.onClearAll,
    super.onHydrate,
    super.onSync,
    super.settings = const PersistorSettings(),
    super.persistenceThrottle = const Duration(milliseconds: 100),
    DataStoreEncrypter? encrypter,
  })  : encrypter = encrypter = encrypter ?? DataStoreEncrypter(),
        logger = Loon.logger.child('FilePersistor');

  /// Initializes the directory in which files are persisted. This needs to be done on the main isolate
  /// as opposed to the worker since it requires access to plugins that are not easily available in the worker
  /// isolate context.
  Future<Directory> _initDirectory() async {
    final applicationDirectory = await getApplicationDocumentsDirectory();
    final fileDirectory = Directory('${applicationDirectory.path}/loon');
    final directory = await fileDirectory.create();

    logger.log('Directory: ${directory.path}');

    return directory;
  }

  @override
  init() async {
    final values = await Future.wait([
      _initDirectory(),
      encrypter.init(),
    ]);
    final directory = values.first as Directory;

    _manager = DataStoreManager(
      persistenceThrottle: persistenceThrottle,
      settings: settings,
      logger: logger,
      onSync: onSync,
      factory: (name, encrypted) => DataStore(
        FileDataStoreConfig(
          name,
          logger: logger,
          file: File('${directory.path}/$name.json'),
          encrypted: encrypted,
          encrypter: encrypter,
        ),
      ),
      resolverConfig: FileDataStoreResolverConfig(
        file: File("${directory.path}/${DataStoreResolver.name}.json"),
      ),
      clearAll: () async {
        try {
          await directory.delete(recursive: true);
        } on PathNotFoundException {
          return;
        }
      },
      getAll: () async {
        final files = directory
            .listSync()
            .whereType<File>()
            .where((file) => _fileRegex.hasMatch(path.basename(file.path)))
            .toList();

        return files.map((file) {
          final match = _fileRegex.firstMatch(path.basename(file.path));
          return match!.group(1)!;
        }).toList();
      },
    );

    await _manager.init();
  }

  @override
  clear(List<Collection> collections) {
    return _manager
        .clear(collections.map((collection) => collection.path).toList());
  }

  @override
  clearAll() {
    return _manager.clearAll();
  }

  @override
  hydrate([refs]) {
    return _manager.hydrate(refs?.map((ref) => ref.path).toList());
  }

  @override
  persist(docs) {
    return _manager.persist(docs);
  }
}
