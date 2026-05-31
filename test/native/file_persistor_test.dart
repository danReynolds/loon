import 'dart:async';
import 'dart:convert';
import 'dart:io';
import 'package:encrypt/encrypt.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:loon/loon.dart';
import 'package:loon/persistor/data_store_encrypter.dart';
import 'package:loon/persistor/file_persistor/file_persistor.dart';
import 'package:loon/persistor/file_persistor/file_persistor_worker.dart'
    show fileRegex;

// ignore: depend_on_referenced_packages
import 'package:path_provider_platform_interface/path_provider_platform_interface.dart';
// ignore: depend_on_referenced_packages
import 'package:plugin_platform_interface/plugin_platform_interface.dart';
import '../core/persistor/persistor_test_runner.dart';

late Directory testDirectory;

class MockPathProvider extends Fake
    with MockPlatformInterfaceMixin
    implements PathProviderPlatform {
  Directory getApplicationDocumentsDirectory() {
    return testDirectory;
  }

  @override
  Future<String> getApplicationDocumentsPath() async {
    return testDirectory.path;
  }
}

DataStoreEncrypter createTestEncrypter() {
  // FlutterSecureStorage does not work in tests, so use a deterministic in-process key.
  return DataStoreEncrypter(
    Encrypter(
      AES(
        Key.fromUtf8('0123456789abcdef0123456789abcdef'),
        mode: AESMode.cbc,
      ),
    ),
  );
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

  group('FilePersistor durability', () {
    final loonDir = Directory('${testDirectory.path}/loon');
    final encrypter = createTestEncrypter();

    tearDown(() async {
      await Loon.clearAll();
      Loon.unsubscribe();
    });

    test('Persists atomically, leaving no .tmp files behind', () async {
      final synced = Completer<void>();
      final persistor = FilePersistor(
        persistenceThrottle: const Duration(milliseconds: 1),
        encrypter: encrypter,
        onSync: () {
          if (!synced.isCompleted) synced.complete();
        },
      );
      Loon.configure(persistor: persistor);

      Loon.collection<Json>('users').doc('1').create({'name': 'User 1'});
      await synced.future;

      expect(await File('${loonDir.path}/__store__.json').exists(), true);

      final tmpFiles = loonDir
          .listSync()
          .whereType<File>()
          .where((file) => file.path.endsWith('.tmp'))
          .toList();
      expect(tmpFiles, isEmpty);
    });

    test('Data store file listing ignores orphaned .tmp files', () {
      // A temp file orphaned by an interrupted atomic write must not be picked
      // up as a data store on the next startup.
      expect(fileRegex.hasMatch('users.json'), true);
      expect(fileRegex.hasMatch('users.encrypted.json'), true);
      expect(fileRegex.hasMatch('users.json.tmp'), false);
      expect(fileRegex.hasMatch('__store__.json.tmp'), false);
    });

    test('Overwrites orphaned .tmp files when rewriting their targets',
        () async {
      final orphanedStoreTmp = File('${loonDir.path}/custom_store.json.tmp');
      final orphanedResolverTmp = File('${loonDir.path}/__resolver__.json.tmp');
      await orphanedStoreTmp.writeAsString('partial store write');
      await orphanedResolverTmp.writeAsString('partial resolver write');

      final synced = Completer<void>();
      Loon.configure(
        persistor: FilePersistor(
          persistenceThrottle: const Duration(milliseconds: 1),
          encrypter: encrypter,
          onSync: () {
            if (!synced.isCompleted) synced.complete();
          },
        ),
      );

      final users = Loon.collection<Json>(
        'users',
        persistorSettings: PersistorSettings(
          key: Persistor.key('custom_store'),
        ),
      );
      users.doc('1').create({'name': 'User 1'});
      await synced.future;

      expect(await orphanedStoreTmp.exists(), false);
      expect(await orphanedResolverTmp.exists(), false);
    });
  });

  group('FilePersistor fault recovery', () {
    final loonDir = Directory('${testDirectory.path}/loon');
    final encrypter = createTestEncrypter();

    FilePersistor newPersistor() => FilePersistor(
          persistenceThrottle: const Duration(milliseconds: 1),
          encrypter: encrypter,
        );

    Future<void> writeDefaultStore() {
      return File('${loonDir.path}/__store__.json').writeAsString(
        jsonEncode({
          "": {
            "users": {
              "__values": {
                "1": {"name": "User 1"}
              }
            }
          }
        }),
      );
    }

    setUp(() {
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
      await writeDefaultStore();
      await File('${loonDir.path}/corrupt.json')
          .writeAsString('{ not valid json');

      Loon.configure(persistor: newPersistor());

      await Loon.hydrate();

      expect(
        Loon.collection<Json>('users').doc('1').get()?.data,
        {"name": "User 1"},
      );
      expect(await File('${loonDir.path}/corrupt.json').exists(), false);
      expect(
        await File('${loonDir.path}/corrupt.json.corrupt').exists(),
        true,
      );
    });

    test('A corrupt encrypted data store file does not fail hydration',
        () async {
      await writeDefaultStore();
      await File('${loonDir.path}/__store__.encrypted.json')
          .writeAsString('not encrypted');

      Loon.configure(persistor: newPersistor());

      await Loon.hydrate();

      expect(
        Loon.collection<Json>('users').doc('1').get()?.data,
        {"name": "User 1"},
      );
      expect(
        await File('${loonDir.path}/__store__.encrypted.json.corrupt').exists(),
        true,
      );
    });

    test('A corrupt resolver file does not fail hydration', () async {
      await writeDefaultStore();
      await File('${loonDir.path}/__resolver__.json')
          .writeAsString('}{ broken');

      Loon.configure(persistor: newPersistor());

      await Loon.hydrate();

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
