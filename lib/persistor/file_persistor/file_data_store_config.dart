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
void _logHydrationFailure(
  File file,
  Logger logger,
  Object error,
  StackTrace stackTrace,
) {
  logger.log(
    'Failed to hydrate ${file.path}, recovering without quarantine: '
    '$error\n$stackTrace',
  );
}

Future<void> _recoverCorruptFile(
  File file,
  Logger logger,
  Object error,
  StackTrace stackTrace,
) async {
  logger.log(
    'Failed to hydrate ${file.path}, quarantining as corrupt: '
    '$error\n$stackTrace',
  );

  try {
    final quarantine = File('${file.path}.corrupt');
    if (await quarantine.exists()) {
      await quarantine.delete();
    }
    await file.rename(quarantine.path);
  } catch (error, stackTrace) {
    logger.log('Failed to quarantine ${file.path}: $error\n$stackTrace');
  }
}

Json _decodeJsonObject(String value, String description) {
  final decoded = jsonDecode(value);
  if (decoded is! Json) {
    throw FormatException('Expected $description to be a JSON object.');
  }

  return decoded;
}

Json _readNestedJsonObject(Object? value, String description) {
  if (value is! Json) {
    throw FormatException('Expected $description to be a JSON object.');
  }

  return value;
}

bool _isInvalidCipherTextException(Object error) {
  // encrypt wraps PointyCastle without exposing its exception types.
  return error.runtimeType.toString() == 'InvalidCipherTextException';
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
              final json = _decodeJsonObject(
                encrypted ? encrypter.decrypt(value) : value,
                'persisted data store',
              );
              final store = ValueStore<ValueStore>();

              for (final entry in json.entries) {
                final resolverPath = entry.key;
                final valueStore = ValueStore.fromJson(
                  _readNestedJsonObject(
                    entry.value,
                    'persisted data store entry "$resolverPath"',
                  ),
                );
                store.write(resolverPath, valueStore);
              }

              return store;
            } on PathNotFoundException {
              return null;
            } on FileSystemException catch (error, stackTrace) {
              _logHydrationFailure(file, logger, error, stackTrace);
              return null;
            } on FormatException catch (error, stackTrace) {
              await _recoverCorruptFile(file, logger, error, stackTrace);
              return null;
            } on ArgumentError catch (error, stackTrace) {
              if (!encrypted) {
                rethrow;
              }
              await _recoverCorruptFile(file, logger, error, stackTrace);
              return null;
            } on Exception catch (error, stackTrace) {
              if (!encrypted || !_isInvalidCipherTextException(error)) {
                rethrow;
              }
              await _recoverCorruptFile(file, logger, error, stackTrace);
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
                _decodeJsonObject(
                  await file.readAsString(),
                  'persisted resolver',
                ),
              );
            } on PathNotFoundException {
              return null;
            } on FileSystemException catch (error, stackTrace) {
              _logHydrationFailure(file, logger, error, stackTrace);
              return null;
            } on FormatException catch (error, stackTrace) {
              await _recoverCorruptFile(file, logger, error, stackTrace);
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
