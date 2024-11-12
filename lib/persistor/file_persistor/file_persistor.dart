import 'dart:async';
import 'dart:io';
import 'package:loon/loon.dart';
import 'package:loon/persistor/file_persistor/file_persistor_worker.dart';
import 'package:loon/persistor/worker/persistor_worker_mixin.dart';
import 'package:path_provider/path_provider.dart';

/// A worker abstraction that creates a background worker isolate to process file persistence/hydration.
class FilePersistor extends Persistor with PersistorWorkerMixin {
  FilePersistor({
    super.onPersist,
    super.onClear,
    super.onClearAll,
    super.onHydrate,
    super.onSync,
    super.encrypter,
    super.settings = const PersistorSettings(),
    super.persistenceThrottle = const Duration(milliseconds: 100),
  }) : super(
          logger: Loon.logger.child('FilePersistor'),
        );

  /// Initializes the directory in which files are persisted. This needs to be done on the main isolate
  /// as opposed to the worker since it requires access to plugins that are not easily available in the worker
  /// isolate context.
  Future<Directory> initDirectory() async {
    final applicationDirectory = await getApplicationDocumentsDirectory();
    final fileDirectory = Directory('${applicationDirectory.path}/loon');
    final directory = await fileDirectory.create();

    logger.log('Directory: ${directory.path}');

    return directory;
  }

  @override
  init() async {
    await spawnWorker(
      FilePersistorWorker.new,
      config: FilePersistorWorkerConfig(
        persistenceThrottle: persistenceThrottle,
        settings: settings,
        encrypter: encrypter,
        directory: await initDirectory(),
      ),
    );
  }

  @override
  hydrate([refs]) async {
    return worker.hydrate(refs);
  }

  @override
  persist(docs) async {
    return worker.persist(docs);
  }

  @override
  clear(collections) async {
    return worker.clear(collections);
  }

  @override
  clearAll() async {
    return worker.clearAll();
  }
}
