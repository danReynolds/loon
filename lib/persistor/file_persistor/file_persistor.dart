import 'dart:async';
import 'dart:io';
import 'dart:isolate';
import 'package:encrypt/encrypt.dart';
import 'package:flutter_secure_storage/flutter_secure_storage.dart';
import 'package:loon/loon.dart';
import 'package:loon/persistor/file_persistor/extensions/document.dart';
import 'package:loon/persistor/file_persistor/file_persistor_worker.dart';
import 'package:loon/persistor/file_persistor/messages.dart';
import 'package:loon/utils.dart';
import 'package:path_provider/path_provider.dart';

class FilePersistorSettings extends PersistorSettings {
  /// By default, a document is persisted to a file by its collection name.
  /// If documents in the same collection should be broken into multiple files (due to large collection sizes, etc)
  /// or documents should be grouped together across different collections (due to small collection sizes, etc) then
  /// the persistenc key can be used to group arbitrary documents together into the same persistence file.
  final String? Function(Document doc)? getPersistenceKey;

  const FilePersistorSettings({
    this.getPersistenceKey,
    super.persistenceEnabled = true,
  });
}

class EncryptedFilePersistorSettings extends FilePersistorSettings {
  /// Whether collections should be encrypted as part of persistence. If encryption is only required for certain collections,
  /// then custom persistor settings can be provided to those specific collections.
  final bool encryptionEnabled;

  EncryptedFilePersistorSettings({
    super.getPersistenceKey,
    super.persistenceEnabled = true,
    this.encryptionEnabled = true,
  });
}

/// A worker abstraction that creates a background worker isolate to process file persistence/hydration.
class FilePersistor extends Persistor {
  /// This persistor's receive port
  late final ReceivePort receivePort;

  /// The worker's send port
  late final SendPort sendPort;

  /// An index of task IDs to the task completer that is resolved when they are completed on the worker.
  final Map<String, Completer> _messageRequestIndex = {};

  final secureStorageKey = 'loon_encrypted_file_persistor_key';

  FilePersistor({
    super.persistenceThrottle = const Duration(milliseconds: 100),
    super.persistorSettings = const FilePersistorSettings(),
    super.onPersist,
    super.onClear,
    super.onClearAll,
    super.onHydrate,
  });

  void _onMessage(dynamic message) {
    switch (message) {
      case DebugMessageResponse messageResponse:
        printDebug(messageResponse.text, label: 'Loon worker');
        break;
      case MessageResponse messageResponse:
        final request = _messageRequestIndex[messageResponse.id];

        // In the case of receiving an error message from the worker, print the error
        // text message on the main isolate and complete any associated request completer like a failed
        // persist operation.
        if (messageResponse is ErrorMessageResponse) {
          printDebug(messageResponse.text, label: 'Loon worker');
          request?.completeError(Exception(messageResponse.text));
        } else {
          request?.complete(messageResponse);
        }
        break;
    }
  }

  Future<T> _sendMessage<T extends MessageResponse>(MessageRequest<T> message) {
    final completer = _messageRequestIndex[message.id] = Completer<T>();
    sendPort.send(message);
    return completer.future;
  }

  /// Initializes the encrypter used for encrypting files. This needs to be done on the main isolate
  /// as opposed to the worker since it requires access to plugins that are not easily available in the worker
  /// isolate context.
  Future<Encrypter?> initEncrypter() async {
    // The encrypter is only initialized if the global settings are encrypted file persistor settings.
    if (persistorSettings is! EncryptedFilePersistorSettings) {
      return null;
    }

    const storage = FlutterSecureStorage();
    final base64Key = await storage.read(key: secureStorageKey);
    Key key;

    if (base64Key != null) {
      key = Key.fromBase64(base64Key);
    } else {
      key = Key.fromSecureRandom(32);
      await storage.write(key: secureStorageKey, value: key.base64);
    }

    return Encrypter(AES(key, mode: AESMode.cbc));
  }

  /// Initializes the directory in which files are persisted. This needs to be done on the main isolate
  /// as opposed to the worker since it requires access to plugins that are not easily available in the worker
  /// isolate context.
  Future<Directory> initDirectory() async {
    final applicationDirectory = await getApplicationDocumentsDirectory();
    final fileDirectory = Directory('${applicationDirectory.path}/loon');
    return fileDirectory.create();
  }

  @override
  Future<void> init() async {
    final [encrypter, directory] = await Future.wait([
      initEncrypter(),
      initDirectory(),
    ]);

    // Create a receive port on the main isolate to receive messages from the worker.
    receivePort = ReceivePort();
    receivePort.listen(_onMessage);

    // The initial message request to the worker contains three necessary values:
    // 1. The persistor's send port that will allow for message passing from the worker.
    // 2. The directory that the worker uses to persist file data stores.
    // 3. The encrypter used by file data stores that have encryption enabled.
    final initMessage = InitMessageRequest(
      sendPort: receivePort.sendPort,
      directory: directory as Directory,
      encrypter: encrypter as Encrypter?,
    );

    final completer =
        _messageRequestIndex[initMessage.id] = Completer<InitMessageResponse>();

    try {
      await measureDuration('Worker spawn', () async {
        return Isolate.spawn(
          FilePersistorWorker.init,
          initMessage,
          debugName: 'Loon worker',
        );
      });

      final response = await completer.future;
      sendPort = response.sendPort;
    } catch (e) {
      printDebug("Failed to initialize file persistor worker");
      receivePort.close();
      rethrow;
    }
  }

  @override
  Future<SerializedCollectionStore> hydrate() async {
    final response = await _sendMessage(HydrateMessageRequest());
    return response.data;
  }

  @override
  Future<void> persist(List<Document> docs) async {
    // Marshall file persist documents to be sent to and persisted by the worker isolate.
    final data = docs.map((doc) => doc.toPersistenceDoc()).toList();
    await _sendMessage(PersistMessageRequest(data: data));
  }

  @override
  Future<void> clear(collection) async {
    await _sendMessage(ClearMessageRequest(collection: collection));
  }

  @override
  Future<void> clearAll() async {
    await _sendMessage(ClearAllMessageRequest());
  }
}
