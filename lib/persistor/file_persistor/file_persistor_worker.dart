import 'dart:io';
import 'dart:isolate';
import 'package:encrypt/encrypt.dart';
import 'package:loon/loon.dart';
import 'package:loon/persistor/file_persistor/file_data_store_manager.dart';
import 'package:loon/persistor/file_persistor/messages.dart';

/// The file persistor worker is run on a background isolate to manage file system operations
/// like the persistence and hydration of documents.
class FilePersistorWorker {
  /// The persistor's send port.
  final SendPort sendPort;

  /// This worker's receive port.
  final receivePort = ReceivePort();

  late final FileDataStoreManager manager;

  static late final Logger logger;

  FilePersistorWorker._({
    required this.sendPort,
    required Directory directory,
    required Encrypter encrypter,
  }) {
    logger = Logger('Worker', output: _sendLog);

    manager = FileDataStoreManager(
      directory: directory,
      encrypter: encrypter,
    );
  }

  static init(InitMessageRequest request) {
    FilePersistorWorker._(
      sendPort: request.sendPort,
      directory: request.directory,
      encrypter: request.encrypter,
    )._onMessage(request);
  }

  _sendResponse(MessageResponse response) {
    sendPort.send(response);
  }

  _sendLog(String text) {
    _sendResponse(LogMessageResponse(text: text));
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
    await manager.init();

    // Start listening to messages from the persistor on the worker's receive port.
    receivePort.listen(_onMessage);

    // Send a successful message response containing the worker's send port.
    _sendResponse(request.success(receivePort.sendPort));
  }

  void _hydrate(HydrateMessageRequest request) {
    logger.measure('Hydration operation', () async {
      try {
        final data = await manager.hydrate(request.paths);
        _sendResponse(request.success(data));
      } catch (e) {
        _sendResponse(request.error('Hydration error'));
      }
    });
  }

  void _persist(PersistMessageRequest request) {
    logger.measure('Persist operation', () async {
      try {
        await manager.persist(request.data);
        _sendResponse(request.success());
      } catch (e) {
        _sendResponse(request.error('Persist error'));
      }
    });
  }

  void _clear(ClearMessageRequest request) {
    logger.measure('Clear operation', () async {
      try {
        await manager.clear(request.paths);
        _sendResponse(request.success());
      } catch (e) {
        _sendResponse(request.error('Clear error'));
      }
    });
  }

  void _clearAll(ClearAllMessageRequest request) {
    logger.measure('ClearAll operation', () async {
      try {
        await manager.clearAll();
        _sendResponse(request.success());
      } catch (e) {
        _sendResponse(request.error('ClearAll failed'));
      }
    });
  }
}
