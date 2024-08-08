import 'dart:async';
import 'dart:io';
import 'dart:isolate';
import 'package:encrypt/encrypt.dart';
import 'package:flutter_secure_storage/flutter_secure_storage.dart';
import 'package:loon/loon.dart';
import 'package:loon/persistor/file_persistor/file_persist_document.dart';
import 'package:loon/persistor/file_persistor/file_persistor_settings.dart';
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

  /// The throttle for batching persisted documents. All documents updated within the throttle
  /// duration are batched together into a single persist operation.
  final Duration persistenceThrottle;

  final void Function()? onSync;

  final _secureStorageKey = 'loon_encrypted_file_persistor_key';

  late final Logger _logger;

  @override
  // ignore: overridden_fields
  final FilePersistorSettings settings;

  FilePersistor({
    super.onPersist,
    super.onClear,
    super.onClearAll,
    super.onHydrate,
    this.onSync,
    this.settings = const FilePersistorSettings(),
    this.persistenceThrottle = const Duration(milliseconds: 100),
  }) {
    _logger = Logger('FilePersistor', output: Loon.logger.log);
  }

  static FilePersistorKey key<T>(String value) {
    return FilePersistorValueKey(value);
  }

  static FilePersistorKey keyBuilder<T>(
    String Function(DocumentSnapshot<T> snap) builder,
  ) {
    return FilePersistorBuilderKey<T>(builder);
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

  /// Initializes the encrypter used for encrypting files. This needs to be done on the main isolate
  /// as opposed to the worker since it requires access to plugins that are not easily available in the worker
  /// isolate context.
  Future<Encrypter?> initEncrypter() async {
    const storage = FlutterSecureStorage();
    final base64Key = await storage.read(key: _secureStorageKey);
    Key key;

    if (base64Key != null) {
      key = Key.fromBase64(base64Key);
    } else {
      key = Key.fromSecureRandom(32);
      await storage.write(key: _secureStorageKey, value: key.base64);
    }

    return Encrypter(AES(key, mode: AESMode.cbc));
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
      HydrateMessageRequest(refs?.map((entity) => entity.path).toList()),
    );
    return response.data;
  }

  @override
  persist(docs) async {
    final Map<String, String?> keys = {};
    final List<FilePersistDocument> persistDocs = [];

    // The documents are iterated in reversed insertion order, so that newer
    // updates to persistor paths are applied versus older ones.
    for (final doc in docs.reversed) {
      final persistorSettings = doc.persistorSettings;
      final globalPersistorSettings = Loon.persistorSettings;

      bool encrypted;

      if (persistorSettings != null) {
        final persistorDoc = persistorSettings.doc;
        final docSettings = persistorSettings.settings;

        encrypted =
            docSettings is FilePersistorSettings && docSettings.encrypted;

        switch (docSettings) {
          case FilePersistorSettings(key: FilePersistorValueKey key):
            String path;

            /// A value key is stored at the parent path of the document unless it is a document
            /// on the root collection, which supports variable collection persistor settings via [Loon.doc].
            if (persistorDoc.parent != Collection.root.path) {
              path = persistorDoc.parent;
            } else {
              path = persistorDoc.path;
            }

            if (!keys.containsKey(path)) {
              keys[path] = key.value;
            }

            break;
          case FilePersistorSettings(key: FilePersistorBuilderKey keyBuilder):
            final snap = persistorDoc.get();
            final path = persistorDoc.path;

            if (keys.containsKey(path)) {
              break;
            }

            if (snap == null) {
              keys[path] = null;
            } else {
              keys[path] = (keyBuilder as dynamic)(snap);
            }

            break;
        }
      } else {
        encrypted = globalPersistorSettings is FilePersistorSettings &&
            globalPersistorSettings.encrypted;
      }

      persistDocs.add(
        FilePersistDocument(
          path: doc.path,
          data: doc.getSerialized(),
          encrypted: encrypted,
        ),
      );
    }

    await _sendMessage(PersistMessageRequest(keys: keys, docs: persistDocs));
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
