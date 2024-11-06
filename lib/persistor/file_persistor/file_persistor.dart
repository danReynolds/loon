import 'dart:async';
import 'dart:io';
import 'dart:isolate';
import 'package:encrypt/encrypt.dart';
import 'package:loon/loon.dart';
import 'package:loon/persistor/data_store_persistence_payload.dart';
import 'package:loon/persistor/file_persistor/file_persistor_worker.dart';
import 'package:loon/persistor/file_persistor/messages.dart';
import 'package:path_provider/path_provider.dart';

/// A worker abstraction that creates a background worker isolate to process file persistence/hydration.
class FilePersistor extends Persistor {
  /// This persistor's receive port
  late final ReceivePort _receivePort;

  /// The worker's send port
  late final SendPort _sendPort;

  /// An index of task IDs to the task completer that is resolved when they are completed on the worker.
  final Map<String, Completer> _messageRequestIndex = {};

  late final Logger _logger;

  FilePersistor({
    super.onPersist,
    super.onClear,
    super.onClearAll,
    super.onHydrate,
    super.onSync,
    super.settings = const PersistorSettings(),
    super.persistenceThrottle = const Duration(milliseconds: 100),
  }) {
    _logger = Logger('FilePersistor', output: Loon.logger.log);
  }

  void _onMessage(dynamic message) {
    switch (message) {
      case LogMessage message:
        _logger.log(message.text);
        break;
      case SyncCompleteMessage _:
        onSync?.call();
        break;
      case MessageResponse messageResponse:
        final request = _messageRequestIndex[messageResponse.id];

        // In the case of receiving an error message from the worker, print the error
        // text message on the main isolate and complete any associated request completer like a failed
        // persist operation.
        if (messageResponse is ErrorMessageResponse) {
          _logger.log(messageResponse.text);
          request?.completeError(Exception(messageResponse.text));
        } else {
          request?.complete(messageResponse);
        }
        break;
    }
  }

  Future<T> _sendMessage<T extends MessageResponse>(MessageRequest<T> message) {
    final completer = _messageRequestIndex[message.id] = Completer<T>();
    _sendPort.send(message);
    return completer.future;
  }

  /// Initializes the directory in which files are persisted. This needs to be done on the main isolate
  /// as opposed to the worker since it requires access to plugins that are not easily available in the worker
  /// isolate context.
  Future<Directory> initDirectory() async {
    final applicationDirectory = await getApplicationDocumentsDirectory();
    final fileDirectory = Directory('${applicationDirectory.path}/loon');
    final directory = await fileDirectory.create();

    _logger.log('Directory: ${directory.path}');

    return directory;
  }

  @override
  init() async {
    final [encrypter, directory] = await Future.wait([
      initEncrypter(),
      initDirectory(),
    ]);

    // Create a receive port on the main isolate to receive messages from the worker.
    _receivePort = ReceivePort();
    _receivePort.listen(_onMessage);

    // The initial message request to the worker contains three necessary values:
    // 1. The persistor's send port that will allow for message passing from the worker.
    // 2. The directory that the worker uses to persist file data stores.
    // 3. The encrypter used by file data stores that have encryption enabled.
    final initMessage = InitMessageRequest(
      sendPort: _receivePort.sendPort,
      directory: directory as Directory,
      encrypter: encrypter as Encrypter,
      persistenceThrottle: persistenceThrottle,
      settings: settings,
    );

    final completer =
        _messageRequestIndex[initMessage.id] = Completer<InitMessageResponse>();

    try {
      await _logger.measure('Worker spawn', () async {
        return Isolate.spawn(
          FilePersistorWorker.init,
          initMessage,
          debugName: 'Loon worker',
        );
      });

      final response = await completer.future;
      _sendPort = response.sendPort;
    } catch (e) {
      _logger.log("Worker initialization failed.");
      _receivePort.close();
      rethrow;
    }
  }

  @override
  hydrate([refs]) async {
    final response = await _sendMessage(
      HydrateMessageRequest(refs?.map((ref) => ref.path).toList()),
    );
    return response.data;
  }

  @override
  persist(docs) async {
    await _sendMessage(
      PersistMessageRequest(payload: DataStorePersistencePayload(docs)),
    );
  }

  @override
  clear(collections) async {
    await _sendMessage(
      ClearMessageRequest(
        paths: collections.map((collection) => collection.path).toList(),
      ),
    );
  }

  @override
  clearAll() async {
    await _sendMessage(ClearAllMessageRequest());
  }
}
