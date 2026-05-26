import 'dart:convert';
import 'dart:io';
import 'package:loon/loon.dart';
import 'package:loon/persistor/data_store.dart';
import 'package:loon/persistor/data_store_resolver.dart';

/// Moves a file that failed to hydrate (corrupt JSON, failed decryption) aside
/// to `<path>.corrupt` and recovers by returning null (an empty store) so that
/// one unreadable file cannot fail hydration of the entire store. The data is
/// preserved for inspection, the `.corrupt` suffix is ignored by the data store
/// file listing, and the next persist for the partition writes a fresh file.
Future<void> _recoverCorruptFile(
  File file,
  Logger logger,
  Object error,
) async {
  logger.log('Failed to hydrate ${file.path}, quarantining as corrupt: $error');
  try {
    final quarantine = File('${file.path}.corrupt');
    if (await quarantine.exists()) {
      await quarantine.delete();
    }
    await file.rename(quarantine.path);
  } catch (e) {
    logger.log('Failed to quarantine ${file.path}: $e');
  }
}

class FileDataStoreConfig extends DataStoreConfig {
  FileDataStoreConfig(
    super.name, {
    required File file,
    required super.encrypter,
    required super.encrypted,
    required super.logger,
  }) : super(
          hydrate: () async {
            try {
              final value = await file.readAsString();
              final json = jsonDecode(
                encrypted ? encrypter.decrypt(value) : value,
              );
              final store = ValueStore<ValueStore>();

              for (final entry in json.entries) {
                final resolverPath = entry.key;
                final valueStore = ValueStore.fromJson(entry.value);
                store.write(resolverPath, valueStore);
              }

              return store;
            } on PathNotFoundException {
              return null;
            } catch (error) {
              await _recoverCorruptFile(file, logger, error);
              return null;
            }
          },
          persist: (store) async {
            final value = jsonEncode(store.extract());

            await file.writeAsString(
              encrypted ? encrypter.encrypt(value) : value,
            );
          },
          delete: () async {
            try {
              await file.delete();
            } on PathNotFoundException {
              return;
            }
          },
        );
}

class FileDataStoreResolverConfig extends DataStoreResolverConfig {
  FileDataStoreResolverConfig({
    required File file,
    required super.logger,
  }) : super(
          hydrate: () async {
            try {
              return ValueRefStore<String>(
                  jsonDecode(await file.readAsString()));
            } on PathNotFoundException {
              return null;
            } catch (error) {
              await _recoverCorruptFile(file, logger, error);
              return null;
            }
          },
          persist: (store) => file.writeAsString(jsonEncode(store.inspect())),
          delete: () async {
            try {
              await file.delete();
            } on PathNotFoundException {
              return;
            }
          },
        );
}
