import 'dart:convert';
import 'dart:io';
import 'package:encrypt/encrypt.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:loon/loon.dart';
import 'package:loon/persistor/data_store_encrypter.dart';
import 'package:loon/persistor/file_persistor/file_persistor.dart';

// ignore: depend_on_referenced_packages
import 'package:path_provider_platform_interface/path_provider_platform_interface.dart';
// ignore: depend_on_referenced_packages
import 'package:plugin_platform_interface/plugin_platform_interface.dart';
import '../core/persistor/persistor_test_runner.dart';

late Directory testDirectory;

class MockPathProvider extends Fake
    with MockPlatformInterfaceMixin
    implements PathProviderPlatform {
  getApplicationDocumentsDirectory() {
    return testDirectory;
  }

  @override
  getApplicationDocumentsPath() async {
    return testDirectory.path;
  }
}

void main() {
  testDirectory = Directory.systemTemp.createTempSync('test_dir');
  Directory("${testDirectory.path}/loon").createSync();
  final mockPathProvider = MockPathProvider();
  PathProviderPlatform.instance = mockPathProvider;

  group('FilePersistor', () {
    persistorTestRunner(
      getStore: (
        persistor,
        name, {
        required encrypted,
      }) async {
        final file = File('${testDirectory.path}/loon/$name.json');

        final exists = await file.exists();
        if (!exists) {
          return null;
        }

        final value = await file.readAsString();

        return jsonDecode(
          encrypted ? persistor.encrypter.decrypt(value) : value,
        );
      },
      factory: FilePersistor.new,
    );
  });

  group('FilePersistor fault recovery', () {
    final loonDir = Directory('${testDirectory.path}/loon');

    // FlutterSecureStorage does not work in tests, so supply a fixed encrypter.
    final encrypter = DataStoreEncrypter(
      Encrypter(AES(Key.fromSecureRandom(32), mode: AESMode.cbc)),
    );

    FilePersistor newPersistor() => FilePersistor(
          persistenceThrottle: const Duration(milliseconds: 1),
          encrypter: encrypter,
        );

    setUp(() {
      // Start each scenario from an empty persistence directory.
      if (loonDir.existsSync()) {
        for (final entity in loonDir.listSync()) {
          entity.deleteSync(recursive: true);
        }
      }
      Loon.unsubscribe();
    });

    tearDown(() async {
      await Loon.clearAll();
      Loon.unsubscribe();
    });

    test('A corrupt data store file does not fail hydration of the rest',
        () async {
      // A valid default store plus an unreadable sibling store on disk.
      await File('${loonDir.path}/__store__.json').writeAsString(
        jsonEncode({
          "": {
            "users": {
              "__values": {"1": {"name": "User 1"}}
            }
          }
        }),
      );
      await File('${loonDir.path}/corrupt.json')
          .writeAsString('{ not valid json');

      Loon.configure(persistor: newPersistor());

      // Hydration must not throw despite the corrupt file.
      await Loon.hydrate();

      // The valid store's data is still hydrated.
      expect(
        Loon.collection<Json>('users').doc('1').get()?.data,
        {"name": "User 1"},
      );

      // The corrupt file was quarantined rather than loaded.
      expect(await File('${loonDir.path}/corrupt.json').exists(), false);
      expect(
        await File('${loonDir.path}/corrupt.json.corrupt').exists(),
        true,
      );
    });

    test('A corrupt resolver file does not fail hydration', () async {
      await File('${loonDir.path}/__store__.json').writeAsString(
        jsonEncode({
          "": {
            "users": {
              "__values": {"1": {"name": "User 1"}}
            }
          }
        }),
      );
      await File('${loonDir.path}/__resolver__.json')
          .writeAsString('}{ broken');

      Loon.configure(persistor: newPersistor());

      await Loon.hydrate();

      // Full hydration does not depend on the resolver, so the data still loads.
      expect(
        Loon.collection<Json>('users').doc('1').get()?.data,
        {"name": "User 1"},
      );
      expect(
        await File('${loonDir.path}/__resolver__.json.corrupt').exists(),
        true,
      );
    });
  });
}
