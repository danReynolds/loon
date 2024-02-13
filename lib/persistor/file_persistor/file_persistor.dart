import 'dart:async';
import 'dart:io';
import 'dart:isolate';
import 'package:loon/loon.dart';
import 'package:loon/persistor/file_persistor/file_persistor_task.dart';
import 'package:loon/persistor/file_persistor/file_persistor_worker.dart';
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

  /// The task runner's receive port
  late final ReceivePort receivePort;

  /// The worker's send port
  late final SendPort sendPort;

  /// An index of task IDs to the task completer that is resolved when they are completed on the worker.
  final Map<String, Completer> _taskIndex = {};

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
      case TaskResponse taskResponse:
        _taskIndex[taskResponse.id]!.complete(taskResponse);
    }
  }

  Future<T> _sendTaskRequest<T extends TaskResponse>(TaskRequest<T> task) {
    final completer = _taskIndex[task.id] = Completer<T>();
    sendPort.send(task);
    return completer.future;
  }

  @override
  Future<void> init() async {
    final directory = await _initStorageDirectory();

    // Create a receive port on the main isolatex to receive messages from the worker.
    receivePort = ReceivePort();
    receivePort.listen(_onMessage);

    final initTaskRequest = InitTaskRequest(
      persistorSettings: persistorSettings,
      sendPort: receivePort.sendPort,
      directory: directory,
    );

    final completer =
        _taskIndex[initTaskRequest.id] = Completer<InitTaskResponse>();

    // Spawn the worker isolate, providing the main isolate's send port for 2-way communication.
    _isolate = await Isolate.spawn(FilePersistorWorker.init, initTaskRequest);

    final response = await completer.future;
    sendPort = response.sendPort;
  }

  @override
  Future<SerializedCollectionStore> hydrate() async {
    final response = await _sendTaskRequest(HydrateTaskRequest());
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
    await _sendTaskRequest(PersistTaskRequest(data: json));
  }

  @override
  Future<void> clear() async {
    await _sendTaskRequest(ClearTaskRequest());
  }
}
