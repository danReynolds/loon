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

  group('FilePersistor durability', () {
    final loonDir = Directory('${testDirectory.path}/loon');

    // FlutterSecureStorage does not work in tests, so supply a fixed encrypter.
    final encrypter = DataStoreEncrypter(
      Encrypter(AES(Key.fromSecureRandom(32), mode: AESMode.cbc)),
    );

    tearDown(() async {
      await Loon.clearAll();
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

    test('Cleans orphaned .tmp files on startup', () async {
      final orphanedStoreTmp = File('${loonDir.path}/users.json.tmp');
      final orphanedResolverTmp = File('${loonDir.path}/__resolver__.json.tmp');
      await orphanedStoreTmp.writeAsString('partial store write');
      await orphanedResolverTmp.writeAsString('partial resolver write');

      Loon.configure(
        persistor: FilePersistor(encrypter: encrypter),
      );
      await Loon.hydrate();

      expect(await orphanedStoreTmp.exists(), false);
      expect(await orphanedResolverTmp.exists(), false);
    });
  });
}
