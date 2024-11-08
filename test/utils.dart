import 'dart:async';
import 'dart:convert';
import 'package:encrypt/encrypt.dart';
import 'package:loon/loon.dart';
import 'package:uuid/uuid.dart';

const uuid = Uuid();
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

Future<void> asyncEvent() {
  return Future.delayed(const Duration(milliseconds: 1), () => null);
}
