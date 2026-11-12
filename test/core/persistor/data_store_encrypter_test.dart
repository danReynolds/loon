import 'package:encrypt/encrypt.dart';
import 'package:flutter/services.dart';
import 'package:flutter_secure_storage/test/test_flutter_secure_storage_platform.dart';
import 'package:flutter_secure_storage_platform_interface/flutter_secure_storage_platform_interface.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:loon/loon.dart';

class _RecordingStorage extends TestFlutterSecureStoragePlatform {
  _RecordingStorage(super.data);

  SecureStorageUpgradeStatus upgradeStatus =
      SecureStorageUpgradeStatus.unsupported;
  bool failRead = false;
  Map<String, String>? lastOptions;
  int writes = 0;

  @override
  Future<SecureStorageUpgradeStatus> checkUpgradeStatus({
    required Map<String, String> options,
  }) async {
    lastOptions = options;
    return upgradeStatus;
  }

  @override
  Future<String?> read({
    required String key,
    required Map<String, String> options,
  }) async {
    lastOptions = options;
    if (failRead) throw PlatformException(code: 'StorageError');
    return super.read(key: key, options: options);
  }

  @override
  Future<void> write({
    required String key,
    required String value,
    required Map<String, String> options,
  }) async {
    writes++;
    lastOptions = options;
    await super.write(key: key, value: value, options: options);
  }
}

void main() {
  TestWidgetsFlutterBinding.ensureInitialized();
  const keyName = 'loon_encrypted_file_persistor_key';
  late FlutterSecureStoragePlatform originalPlatform;
  late _RecordingStorage storage;

  setUp(() {
    originalPlatform = FlutterSecureStoragePlatform.instance;
    storage = _RecordingStorage({});
    FlutterSecureStoragePlatform.instance = storage;
  });
  tearDown(() => FlutterSecureStoragePlatform.instance = originalPlatform);

  test('new key is persisted with non-destructive Android options', () async {
    final encrypter = DataStoreEncrypter();
    await encrypter.init();
    expect(storage.data[keyName], isNotNull);
    expect(Key.fromBase64(storage.data[keyName]!).bytes.length, 32);
    expect(storage.lastOptions!['resetOnError'], 'false');
    expect(storage.lastOptions!['migrateOnAlgorithmChange'], 'true');
    expect(storage.lastOptions!['storageNamespace'], '');
    expect(storage.writes, 1);
  });

  test('existing key survives initialization without rewriting', () async {
    final original = Key.fromSecureRandom(32).base64;
    storage.data[keyName] = original;
    await DataStoreEncrypter().init();
    expect(storage.data[keyName], original);
    expect(storage.writes, 0);
  });

  test('unreadable legacy data cannot cause a replacement key', () async {
    storage.upgradeStatus = const SecureStorageUpgradeStatus(
      state: SecureStorageUpgradeState.legacyDataUnreadable,
    );
    await expectLater(DataStoreEncrypter().init(), throwsStateError);
    expect(storage.writes, 0);
    expect(storage.data, isEmpty);
  });

  test('uncertain status cannot cause a replacement key', () async {
    storage.upgradeStatus = const SecureStorageUpgradeStatus(
      state: SecureStorageUpgradeState.unknown,
    );
    await expectLater(DataStoreEncrypter().init(), throwsStateError);
    expect(storage.writes, 0);
  });

  test('storage read error propagates without replacing the key', () async {
    storage.failRead = true;
    await expectLater(
        DataStoreEncrypter().init(), throwsA(isA<PlatformException>()));
    expect(storage.writes, 0);
  });
}
