import 'dart:convert';
import 'package:encrypt/encrypt.dart';
import 'package:fake_async/fake_async.dart';
import 'package:loon/loon.dart';

final testEncryptionKey = Key.fromSecureRandom(32);

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

/// Advances past Loon's zero-duration broadcast timer and drains stream delivery.
void flushBroadcasts(FakeAsync async) {
  elapseAndFlush(async, const Duration(milliseconds: 1));
}

/// Advances fake time and drains microtasks around any timer callbacks.
void elapseAndFlush(FakeAsync async, Duration duration) {
  async.flushMicrotasks();
  async.elapse(duration);
  async.flushMicrotasks();
}
