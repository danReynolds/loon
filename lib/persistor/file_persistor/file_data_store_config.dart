import 'dart:convert';
import 'dart:io';
import 'package:loon/loon.dart';
import 'package:loon/persistor/data_store.dart';
import 'package:loon/persistor/data_store_resolver.dart';

class FileDataStoreConfig extends DataStoreConfig {
  FileDataStoreConfig(
    super.name, {
    required File file,
    required super.encrypted,
    required super.encrypter,
    required super.logger,
  }) : super(
          hydrate: () async {
            final value = await file.readAsString();
            final json =
                jsonDecode(encrypted ? encrypter.decrypt(value) : value);
            final store = ValueStore<ValueStore>();

            for (final entry in json.entries) {
              final resolverPath = entry.key;
              final valueStore = ValueStore.fromJson(entry.value);
              store.write(resolverPath, valueStore);
            }

            return store;
          },
          persist: (store) async {
            final value = jsonEncode(store.extract());

            await file.writeAsString(
              encrypted ? encrypter.encrypt(value) : value,
            );
          },
          delete: () => file.delete(),
        );
}

class FileDataStoreResolverConfig extends DataStoreResolverConfig {
  FileDataStoreResolverConfig({
    required File file,
  }) : super(
          hydrate: () async =>
              ValueRefStore<String>(jsonDecode(await file.readAsString())),
          persist: (store) => file.writeAsString(jsonEncode(store.inspect())),
          delete: () => file.delete(),
        );
}
