import 'dart:convert';
import 'dart:io';
import 'package:flutter_test/flutter_test.dart';
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
        bool encrypted = false,
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
}
