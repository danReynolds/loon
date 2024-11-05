import 'dart:async';
import 'dart:io';
import 'dart:isolate';
import 'package:encrypt/encrypt.dart';
import 'package:loon/loon.dart';
import 'package:loon/persistor/data_store_manager.dart';
import 'package:loon/persistor/file_persistor/file_data_store.dart';
import 'package:loon/persistor/file_persistor/messages.dart';
import 'package:path/path.dart' as path;

/// The file persistor worker is run on a background isolate to manage file system operations
/// like the persistence and hydration of documents.
class FilePersistorWorker {
  /// The persistor's send port.
  final SendPort sendPort;

  /// This worker's receive port.
  final receivePort = ReceivePort();

  late final DataStoreManager manager;

  static late final Logger logger;

  FilePersistorWorker._({
    required this.sendPort,
    required Directory directory,
    required Encrypter encrypter,
    required Duration persistenceThrottle,
    required PersistorSettings settings,
  }) {
    logger = Logger('Worker', output: _sendLogMessage);
  }

  static init(InitMessageRequest request) {
    FilePersistorWorker._(
      sendPort: request.sendPort,
      directory: request.directory,
      encrypter: request.encrypter,
      persistenceThrottle: request.persistenceThrottle,
      settings: request.settings,
    )._onMessage(request);
  }

  void _sendLogMessage(String text) {
    _sendMessage(LogMessage(text: text));
  }

  void _sendSyncMessage() {
    _sendMessage(SyncCompleteMessage());
  }

  void _sendMessage(Message message) {
    sendPort.send(message);
  }

  void _onMessage(dynamic message) {
    switch (message) {
      case InitMessageRequest request:
        _init(request);
      case HydrateMessageRequest request:
        _hydrate(request);
      case PersistMessageRequest request:
        _persist(request);
      case ClearMessageRequest request:
        _clear(request);
      case ClearAllMessageRequest request:
        _clearAll(request);
      default:
        break;
    }
  }

  ///
  /// Message request handlers
  ///

  Future<void> _init(InitMessageRequest request) async {
    final directory = request.directory;
    final encrypter = request.encrypter;

    final Map<String, FileDataStore> index = {};
    final files = directory
        .listSync()
        .whereType<File>()
        .where((file) => fileRegex.hasMatch(path.basename(file.path)))
        .toList();

    for (final file in files) {
      final match = fileRegex.firstMatch(path.basename(file.path));
      final name = match!.group(1)!;

      // De-dupe the plaintext/encrypted files for the same data store.
      if (!index.containsKey(name)) {
        index[name] = FileDataStore.parse(
          name,
          encrypter: request.encrypter,
          directory: directory,
        );
      }
    }

    final resolver = FileDataStoreResolver(directory: directory);
    await resolver.hydrate();

    manager = DataStoreManager(
      encrypter: request.encrypter,
      persistenceThrottle: request.persistenceThrottle,
      settings: request.settings,
      onSync: _sendSyncMessage,
      onLog: _sendLogMessage,
      index: index,
      resolver: resolver,
      factory: (name) => FileDataStore(
        name,
        directory: directory,
        encrypter: encrypter,
        isHydrated: true,
      ),
    );

    // Start listening to messages from the persistor on the worker's receive port.
    receivePort.listen(_onMessage);

    // Send a successful message response containing the worker's send port.
    _sendMessage(request.success(receivePort.sendPort));
  }

  void _hydrate(HydrateMessageRequest request) {
    logger.measure('Hydration operation', () async {
      try {
        final data = await manager.hydrate(request.paths);
        _sendMessage(request.success(data));
      } catch (e) {
        _sendMessage(request.error('Hydration error'));
      }
    });
  }

  void _persist(PersistMessageRequest request) {
    logger.measure('Persist operation', () async {
      try {
        logger.log('Persist operation batch size: ${request.docs.length}');
        await manager.persist(request.resolver, request.docs);
        _sendMessage(request.success());
      } catch (e) {
        _sendMessage(request.error('Persist error'));
      }
    });
  }

  void _clear(ClearMessageRequest request) {
    logger.measure('Clear operation', () async {
      try {
        await manager.clear(request.paths);
        _sendMessage(request.success());
      } catch (e) {
        _sendMessage(request.error('Clear error'));
      }
    });
  }

  void _clearAll(ClearAllMessageRequest request) {
    logger.measure('ClearAll operation', () async {
      try {
        await manager.clearAll();
        _sendMessage(request.success());
      } catch (e) {
        _sendMessage(request.error('ClearAll failed'));
      }
    });
  }
}
