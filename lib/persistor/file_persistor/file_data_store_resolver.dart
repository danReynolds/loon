import 'dart:convert';
import 'dart:io';

import 'package:loon/loon.dart';
import 'package:loon/persistor/data_store_resolver.dart';
import 'package:loon/persistor/file_persistor/file_persistor_worker.dart';

class FileDataStoreResolver extends DataStoreResolver {
  late final File _file;
  late final Logger _logger;

  FileDataStoreResolver({
    required Directory directory,
  }) {
    _logger = Logger(
      'FileDataStoreResolver',
      output: FilePersistorWorker.logger.log,
    );
    _file = File("${directory.path}/${DataStoreResolver.name}.json");
  }

  @override
  Future<void> hydrate() async {
    try {
      await _logger.measure(
        'Hydrate',
        () async {
          if (await (_file.exists())) {
            final fileStr = await _file.readAsString();
            store = ValueRefStore<String>(jsonDecode(fileStr));
          }
        },
      );
    } catch (e) {
      // If hydration fails for an existing file, then this file data store is corrupt
      // and should be removed from the file data store index.
      _logger.log('Corrupt file.');
      rethrow;
    }
  }

  @override
  Future<void> persist() async {
    if (store.isEmpty) {
      _logger.log('Empty persist');
      return;
    }

    await _logger.measure(
      'Persist',
      () => _file.writeAsString(jsonEncode(store.inspect())),
    );
  }

  @override
  Future<void> delete() async {
    await _logger.measure(
      'Delete',
      () async {
        if (await _file.exists()) {
          await _file.delete();
        }
        store.clear();
        // Re-initialize the root of the store to the default persistor key.
        store.write(ValueStore.root, Persistor.defaultKey.value);
      },
    );
  }
}
