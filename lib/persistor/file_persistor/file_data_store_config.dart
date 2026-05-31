import 'dart:convert';
import 'dart:io';
import 'package:loon/loon.dart';
import 'package:loon/persistor/data_store.dart';
import 'package:loon/persistor/data_store_resolver.dart';

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

/// Moves a file that failed to hydrate (corrupt JSON, failed decryption) aside
/// to `<path>.corrupt` and recovers by returning null (an empty store) so that
/// one unreadable file cannot fail hydration of the entire store. The data is
/// preserved for inspection, the `.corrupt` suffix is ignored by the data store
/// file listing, and the next persist for the partition writes a fresh file.
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

/// Writes [contents] to [file] atomically: the data is written to a sibling
/// temporary file, flushed to disk, then renamed over the target. A rename on
/// the same filesystem is atomic, so an interrupted write (crash, OOM kill,
/// power loss) can never leave the target torn — it always holds either the
/// complete previous contents or the complete new contents. A plain
/// `writeAsString` truncates the target up front, leaving a window where a
/// crash corrupts it.
///
/// The `.tmp` suffix is deliberately not matched by the data store file listing
/// (`fileRegex` in the worker), so a temp file orphaned by an interrupted write
/// is ignored and overwritten by the next write to the same target rather than
/// loaded as a store.
Future<void> _writeFileAtomic(File file, String contents) async {
  final tmpFile = File('${file.path}.tmp');

  try {
    final raf = await tmpFile.open(mode: FileMode.writeOnly);
    try {
      await raf.writeString(contents);
      // Flush the data to disk before the rename so the rename can't expose an
      // empty/partial file after a power loss.
      await raf.flush();
    } finally {
      await raf.close();
    }

    await tmpFile.rename(file.path);
  } catch (_) {
    // Best-effort cleanup for normal write failures. This will not run after a
    // process crash; the next write to this target overwrites the stale temp.
    try {
      await tmpFile.delete();
    } on FileSystemException {
      // Preserve the original write error if cleanup also fails.
    }
    rethrow;
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
              String contents;
              if (encrypted) {
                try {
                  contents = encrypter.decrypt(value);
                } catch (error, stackTrace) {
                  await _recoverCorruptFile(file, logger, error, stackTrace);
                  return null;
                }
              } else {
                contents = value;
              }

              final json = jsonDecode(contents);
              final store = ValueStore<ValueStore>();

              for (final entry in json.entries) {
                final resolverPath = entry.key;
                final valueStore = ValueStore.fromJson(entry.value);
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
            }
          },
          persist: (store) async {
            final value = jsonEncode(store.extract());

            await _writeFileAtomic(
              file,
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
              final json = jsonDecode(await file.readAsString());
              return ValueRefStore<String>(json);
            } on PathNotFoundException {
              return null;
            }
          },
          persist: (store) =>
              _writeFileAtomic(file, jsonEncode(store.inspect())),
          delete: () async {
            try {
              await file.delete();
            } on PathNotFoundException {
              return;
            }
          },
        );
}
