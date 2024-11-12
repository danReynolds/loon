import 'dart:async';
import 'dart:isolate';
import 'package:loon/loon.dart';
import 'package:loon/persistor/worker/messages.dart';
import 'package:loon/persistor/worker/persistor_worker.dart';
import 'package:loon/persistor/worker/persistor_worker_messenger.dart';

/// The entrypoint for the background worker isolate. This should be a global function
/// to capture as little state as possible to prevent it being copied to the worker isolate.
Future<void>
    _entrypoint<T extends PersistorWorker, S extends PersistorWorkerConfig>(
  EntrypointArgs<T, S> args,
) async {
  final worker = args.factory(args.config);
  worker.onMessage(args.message);
}

/// Mixin that enables the spawning of a [PersistorWorker] by the persistor for offloading operations
/// to a background isolate.
mixin PersistorWorkerMixin on Persistor {
  late final PersistorWorkerMessenger worker;

  /// Spawns an instance of the worker specified by the [factory] on a background isolate
  /// and returns a [PersistorWorkerMessenger] for communicating with the spawned worker.
  Future<void> spawnWorker<T extends PersistorWorker<S>,
      S extends PersistorWorkerConfig>(
    T Function(S config) factory, {
    required S config,
  }) async {
    worker = PersistorWorkerMessenger(logger: logger, onSync: onSync);
    final message = InitMessageRequest(sendPort: worker.receivePort.sendPort);
    final completer = worker.index[message.id] = Completer();

    // The encrypter must be initialized on the main isolate. If it has not been done so yet,
    // then initialize it before spawning the worker.
    await encrypter.init();

    await Isolate.spawn(
      _entrypoint<T, S>,
      EntrypointArgs(
        config: config,
        factory: factory,
        message: message,
        encrypter: encrypter,
      ),
      debugName: 'PersistorWorker',
    );

    return completer.future;
  }
}
