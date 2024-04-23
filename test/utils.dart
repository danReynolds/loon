import 'dart:async';
import 'dart:convert';
import 'dart:io';
import 'dart:math';
import 'package:encrypt/encrypt.dart';
import 'package:loon/loon.dart';
import 'package:uuid/uuid.dart';
import './models/test_large_model.dart';

const uuid = Uuid();
final testEncryptionKey = Key.fromSecureRandom(32);

/// A type of completer that is reset after its current completion result is observed by a subscriber
/// to its future.
class ResetCompleter<T> {
  Completer<T> _completer = Completer();

  void complete([T? value]) {
    if (!_completer.isCompleted) {
      _completer.complete(value);
    }
  }

  Future<void> get future async {
    await _completer.future;
    _completer = Completer<T>();
  }
}

class PersistorCompleter {
  final _onPersistCompleter = ResetCompleter();
  final _onClearCompleter = ResetCompleter();
  final _onHydrateCompleter = ResetCompleter();
  final _onClearAllCompleter = ResetCompleter();

  void persistComplete() {
    _onPersistCompleter.complete();
  }

  void clearComplete() {
    _onClearCompleter.complete();
  }

  void clearAllComplete() {
    _onClearAllCompleter.complete();
  }

  void hydrateComplete() {
    _onHydrateCompleter.complete();
  }

  Future<void> get onPersistComplete {
    return _onPersistCompleter.future;
  }

  Future<void> get onClearComplete {
    return _onClearCompleter.future;
  }

  Future<void> get onClearAllComplete {
    return _onClearAllCompleter.future;
  }

  Future<void> get onHydrateComplete {
    return _onHydrateCompleter.future;
  }
}

TestLargeModel generateRandomModel() {
  var random = Random();
  return TestLargeModel(
    id: uuid.v4(),
    amount: random.nextDouble() * 100,
    name: 'Name ${random.nextInt(100)}',
    createdAt: DateTime.now().subtract(Duration(days: random.nextInt(100))),
    updatedAt: DateTime.now(),
    secondaryAmount: random.nextDouble() * 200,
    description: 'Description ${random.nextInt(100)}',
  );
}

Future<void> generateLargeModelSampleFile(int size) {
  List<TestLargeModel> models =
      List.generate(size, (_) => generateRandomModel());

  final modelsMap = models.fold({}, (acc, model) {
    acc['users:${model.id}'] = model.toJson();
    return acc;
  });

  String jsonContent = jsonEncode(modelsMap);
  File file = File('./test/samples/large_model_sample.json');
  return file.writeAsString(jsonContent);
}

String encryptData(Json json) {
  final iv = IV.fromSecureRandom(16);
  final encrypter = Encrypter(AES(testEncryptionKey, mode: AESMode.cbc));
  return iv.base64 + encrypter.encrypt(jsonEncode(json), iv: iv).base64;
}

Json decryptData(String encrypted) {
  final encrypter = Encrypter(AES(testEncryptionKey, mode: AESMode.cbc));
  final iv = IV.fromBase64(encrypted.substring(0, 24));
  return jsonDecode(
    encrypter.decrypt64(
      encrypted.substring(24),
      iv: iv,
    ),
  );
}
