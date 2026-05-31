import 'dart:convert';
import 'dart:io';
import 'package:loon/loon.dart';
import 'package:loon/persistor/data_store.dart';
import 'package:loon/persistor/data_store_resolver.dart';

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
/// is ignored and deleted before the next write to the same target rather than
/// loaded as a store.
Future<void> _writeFileAtomic(File file, String contents) async {
  final tmpFile = File('${file.path}.tmp');

  try {
    await tmpFile.delete();
  } on PathNotFoundException {
    // No stale temp file from a previous interrupted write.
  }

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
    // process crash; the next write to this target removes the stale temp file.
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
              return ValueRefStore<String>(
                  jsonDecode(await file.readAsString()));
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
