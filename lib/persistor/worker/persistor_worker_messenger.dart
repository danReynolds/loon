import 'dart:async';
import 'dart:isolate';
import 'package:loon/loon.dart';
import 'package:loon/persistor/data_store_encrypter.dart';
import 'package:loon/persistor/persist_payload.dart';
import 'package:loon/persistor/worker/messages.dart';
import 'package:loon/persistor/worker/persistor_worker.dart';

/// The main isolate messenger for communicating with the background worker.
class PersistorWorkerMessenger {
  /// This main isolate receive port.
  final receivePort = ReceivePort();

  /// The worker isolate send port.
  late final SendPort sendPort;

  /// An index of request IDs to the request completer that is resolved when a response message
  /// is sent back from the worker.
  final Map<String, Completer> index = {};

  final Logger logger;
  final void Function()? onSync;

  PersistorWorkerMessenger({
    required this.logger,
    required this.onSync,
  }) {
    receivePort.listen(_onMessage);
  }

  void _onMessage(dynamic message) {
    switch (message) {
      case LogMessage message:
        logger.log(message.text);
        break;
      case SyncCompleteMessage _:
        onSync?.call();
        break;
      case MessageResponse response:
        final request = index[response.id];

        if (response is InitMessageResponse) {
          sendPort = response.sendPort;
        }

        // In the case of receiving an error message from the worker, print the error
        // text message on the main isolate and complete any associated request completer with the error.
        if (response is ErrorMessageResponse) {
          logger.log(response.text);
          request?.completeError(Exception(response.text));
        } else {
          request?.complete(response);
        }
        break;
    }
  }

  Future<T> _sendMessage<T extends MessageResponse>(MessageRequest<T> message) {
    final completer = index[message.id] = Completer<T>();
    sendPort.send(message);
    return completer.future;
  }

  Future<void> persist(List<Document<dynamic>> docs) async {
    await _sendMessage(
      PersistMessageRequest(payload: PersistPayload(docs)),
    );
  }

  Future<Json> hydrate([List<StoreReference>? refs]) async {
    final response = await _sendMessage(
      HydrateMessageRequest(refs?.map((ref) => ref.path).toList()),
    );
    return response.data;
  }

  Future<void> clear(List<Collection<dynamic>> collections) async {
    await _sendMessage(
      ClearMessageRequest(
        paths: collections.map((collection) => collection.path).toList(),
      ),
    );
  }

  Future<void> clearAll() async {
    await _sendMessage(ClearAllMessageRequest());
  }
}

class EntrypointArgs<T extends PersistorWorker,
    S extends PersistorWorkerConfig> {
  final T Function(S config) factory;
  final S config;
  final InitMessageRequest message;
  final DataStoreEncrypter? encrypter;

  EntrypointArgs({
    required this.message,
    required this.config,
    required this.factory,
    required this.encrypter,
  });
}
