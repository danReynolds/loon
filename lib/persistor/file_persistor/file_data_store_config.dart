import 'dart:convert';
import 'dart:io';
import 'package:loon/loon.dart';
import 'package:loon/persistor/data_store.dart';
import 'package:loon/persistor/data_store_resolver.dart';

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
