import 'dart:async';
import 'dart:io';
import 'dart:isolate';
import 'package:loon/loon.dart';
import 'package:loon/persistor/file_persistor/file_persistor_worker.dart';
import 'package:loon/persistor/file_persistor/messages.dart';
import 'package:path_provider/path_provider.dart';

class FilePersistorSettings<T> extends PersistorSettings<T> {
  /// By default, a document is persisted to a file by its collection name.
  /// If documents in the same collection should be broken into multiple files (due to large collection sizes, etc)
  /// or documents should be grouped together across different collections (due to small collection sizes, etc) then
  /// the persistenc key can be used to group arbitrary documents together into the same persistence file.
  final String? Function(Document doc)? getPersistenceKey;

  FilePersistorSettings({
    this.getPersistenceKey,
    super.persistenceEnabled = true,
  });
}

/// A worker abstraction that creates a background worker isolate to process file persistence/hydration.
class FilePersistor extends Persistor {
  late final Isolate _isolate;

  /// This persistor's receive port
  late final ReceivePort receivePort;

  /// The worker's send port
  late final SendPort sendPort;

  /// An index of task IDs to the task completer that is resolved when they are completed on the worker.
  final Map<String, Completer> _messageRequestIndex = {};

  FilePersistor({
    super.persistenceThrottle = const Duration(milliseconds: 100),
    super.persistorSettings,
    super.onPersist,
    super.onClear,
    super.onHydrate,
  });

  Future<Directory> _initStorageDirectory() async {
    final applicationDirectory = await getApplicationDocumentsDirectory();
    final fileDirectory = Directory('${applicationDirectory.path}/loon');
    return fileDirectory.create();
  }

  void _onMessage(dynamic message) {
    switch (message) {
      case MessageResponse messageResponse:
        _messageRequestIndex[messageResponse.id]!.complete(messageResponse);
    }
  }

  Future<T> _sendMessage<T extends MessageResponse>(MessageRequest<T> message) {
    final completer = _messageRequestIndex[message.id] = Completer<T>();
    sendPort.send(message);
    return completer.future;
  }

  @override
  Future<void> init() async {
    final directory = await _initStorageDirectory();

    // Create a receive port on the main isolatex to receive messages from the worker.
    receivePort = ReceivePort();
    receivePort.listen(_onMessage);

    // The initial message request to the worker contains three necessary values:
    // 1. The persistor's send port that will allow for message passing from the worker.
    // 2. The persistor settings that the worker uses to manage file data stores.
    // 3. The directory in which to store files. This is created on the main isolate since it uses
    //    APIs like `getApplicationDocumentsDirectory` that are not easily available on an isolate.
    final initMessage = InitMessageRequest(
      sendPort: receivePort.sendPort,
      persistorSettings: persistorSettings,
      directory: directory,
    );

    final completer =
        _messageRequestIndex[initMessage.id] = Completer<InitMessageResponse>();

    _isolate = await Isolate.spawn(FilePersistorWorker.init, initMessage);

    final response = await completer.future;
    sendPort = response.sendPort;
  }

  @override
  Future<SerializedCollectionStore> hydrate() async {
    final response = await _sendMessage(HydrateMessageRequest());
    return response.data;
  }

  @override
  Future<void> persist(List<Document> docs) async {
    final json = docs.fold<Map<Document, Json?>>(
      {},
      (acc, doc) {
        acc[doc] = doc.getJson();
        return acc;
      },
    );
    await _sendMessage(PersistMessageRequest(data: json));
  }

  @override
  Future<void> clear() async {
    await _sendMessage(ClearMessageRequest());
  }
}
