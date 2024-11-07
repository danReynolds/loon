import 'dart:convert';
import 'dart:io';
import 'package:loon/loon.dart';
import 'package:loon/persistor/data_store.dart';

final fileRegex = RegExp(r'^(?!__resolver__)(\w+?)(?:.encrypted)?\.json$');

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
            final index = ValueStore<ValueStore>();

            for (final entry in json.entries) {
              final resolverPath = entry.key;
              final valueStore = ValueStore.fromJson(entry.value);
              index.write(resolverPath, valueStore);
            }

            return index;
          },
          persist: (index) async {
            final value = jsonEncode(index.extract());

            await file.writeAsString(
              encrypted ? encrypter.encrypt(value) : value,
            );
          },
          delete: () => file.delete(),
        );
}
