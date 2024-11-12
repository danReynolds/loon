import 'dart:async';
import 'dart:isolate';
import 'dart:ui';
import 'package:loon/loon.dart';
import 'package:loon/persistor/data_store_encrypter.dart';
import 'package:loon/persistor/persist_payload.dart';
import 'package:loon/persistor/worker/messages.dart';

class PersistorWorkerConfig {
  final PersistorSettings settings;
  final Duration persistenceThrottle;
  final DataStoreEncrypter encrypter;
  final RootIsolateToken token = RootIsolateToken.instance!;

  PersistorWorkerConfig({
    required this.settings,
    required this.encrypter,
    required this.persistenceThrottle,
  });
}

/// The background worker.
abstract class PersistorWorker<T extends PersistorWorkerConfig> {
  /// The main isolate send port.
  late final SendPort _sendPort;

  /// The background worker receive port.
  final _receivePort = ReceivePort();

  final T config;

  late final Logger logger = Logger('Worker', output: _sendLogMessage);

  PersistorWorker(this.config) {
    _receivePort.listen(onMessage);
  }

  void _sendLogMessage(String text) {
    _sendMessage(LogMessage(text: text));
  }

  void _sendMessage(Message message) {
    _sendPort.send(message);
  }

  Future<void> onMessage(dynamic message) async {
    switch (message) {
      case MessageRequest request:
        try {
          switch (request) {
            case InitMessageRequest request:
              _sendPort = request.sendPort;
              await init();
              _sendMessage(request.success(_receivePort.sendPort));
            case HydrateMessageRequest request:
              final result = await hydrate(request.paths);
              _sendMessage(request.success(result));
            case PersistMessageRequest request:
              await persist(request.payload);
              _sendMessage(request.success());
            case ClearMessageRequest request:
              await clear(request.paths);
              _sendMessage(request.success());
            case ClearAllMessageRequest request:
              await clearAll();
              _sendMessage(request.success());
            default:
              break;
          }
        } catch (e) {
          _sendMessage(request.error('Request error: $e'));
          rethrow;
        }
      default:
        throw 'Unsupported payload';
    }
  }

  void onSync() {
    _sendMessage(SyncCompleteMessage());
  }

  ///
  /// Worker request handlers
  ///

  Future<void> init();

  Future<void> persist(PersistPayload payload);

  Future<Map<String, dynamic>> hydrate(List<String>? paths);

  Future<void> clear(List<String> collections);

  Future<void> clearAll();
}
