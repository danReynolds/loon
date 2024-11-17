import 'dart:async';
import 'dart:io';
import 'package:loon/persistor/data_store.dart';
import 'package:loon/persistor/data_store_manager.dart';
import 'package:loon/persistor/data_store_resolver.dart';
import 'package:loon/persistor/file_persistor/file_data_store_config.dart';
import 'package:loon/persistor/worker/persistor_worker.dart';
import 'package:path/path.dart' as path;

final fileRegex = RegExp(r'^(?!__resolver__)(\w+?)(?:.encrypted)?\.json$');

class FilePersistorWorkerConfig extends PersistorWorkerConfig {
  final Directory directory;

  FilePersistorWorkerConfig({
    required super.persistenceThrottle,
    required super.settings,
    required super.encrypter,
    required this.directory,
  });
}

class FilePersistorWorker extends PersistorWorker<FilePersistorWorkerConfig> {
  FilePersistorWorker(super.config);

  late final DataStoreManager _manager = DataStoreManager(
    persistenceThrottle: config.persistenceThrottle,
    settings: config.settings,
    logger: logger,
    onSync: onSync,
    encrypter: config.encrypter,
    factory: (name, encrypted, encrypter) => DataStore(
      FileDataStoreConfig(
        name,
        logger: logger,
        file: File('${config.directory.path}/$name.json'),
        encrypted: encrypted,
        encrypter: encrypter,
      ),
    ),
    resolverConfig: FileDataStoreResolverConfig(
      logger: logger,
      file: File("${config.directory.path}/${DataStoreResolver.name}.json"),
    ),
    clearAll: () async {
      try {
        await config.directory.delete(recursive: true);
        await config.directory.create();
      } on PathNotFoundException {
        return;
      }
    },
    getAll: () async {
      final files = config.directory
          .listSync()
          .whereType<File>()
          .where((file) => fileRegex.hasMatch(path.basename(file.path)))
          .toList();

      return files.map((file) {
        final match = fileRegex.firstMatch(path.basename(file.path));
        return match!.group(1)!;
      }).toList();
    },
  );

  @override
  init() async {
    await _manager.init();
  }

  @override
  hydrate(paths) async {
    return _manager.hydrate(paths);
  }

  @override
  persist(payload) {
    return _manager.persist(payload);
  }

  @override
  clear(List<String> collections) {
    return _manager.clear(collections);
  }

  @override
  Future<void> clearAll() {
    return _manager.clearAll();
  }
}
