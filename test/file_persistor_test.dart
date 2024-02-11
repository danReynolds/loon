import 'dart:async';
import 'dart:convert';
import 'dart:io';
import 'package:flutter_test/flutter_test.dart';
import 'package:loon/loon.dart';
import 'package:loon/persistor/file_persistor/file_persistor.dart';

// ignore: depend_on_referenced_packages
import 'package:path_provider_platform_interface/path_provider_platform_interface.dart';
// ignore: depend_on_referenced_packages
import 'package:plugin_platform_interface/plugin_platform_interface.dart';

import 'models/test_user_model.dart';

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
  late Completer onPersistCompleter;

  setUp(() async {
    testDirectory = await Directory.systemTemp.createTemp('test_dir');
    final mockPathProvider = MockPathProvider();
    PathProviderPlatform.instance = mockPathProvider;
    onPersistCompleter = Completer();

    Loon.configure(
      persistor: FilePersistor(
        persistenceThrottle: const Duration(milliseconds: 1),
        onPersist: (_) {
          onPersistCompleter.complete();
        },
      ),
    );
  });

  test(
    'Persists collection to Json file',
    () async {
      final userCollection = Loon.collection(
        'users',
        fromJson: TestUserModel.fromJson,
        toJson: (user) => user.toJson(),
      );

      userCollection.doc('1').create(TestUserModel('User 1'));
      userCollection.doc('2').create(TestUserModel('User 2'));

      await onPersistCompleter.future;

      final file = File('${testDirectory.path}/loon/users.json');
      final json = jsonDecode(file.readAsStringSync());

      expect(
        json,
        {
          'users:1': {'name': 'User 1'},
          'users:2': {'name': 'User 2'}
        },
      );
    },
  );
}
