import 'dart:math';
import 'dart:typed_data';

// 64-characters (2^6)
const String _alphabet =
    '_-0123456789abcdefghijklmnopqrstuvwxyzABCDEFGHIJKLMNOPQRSTUVWXYZ';
final Uint8List _alphabytes = Uint8List.fromList(_alphabet.codeUnits);
const int _u32 = 0x100000000; // 2^32

final Random _secureRandom = Random.secure();
final Random _fastRandom = Random();

String _generateRandomId(Random random, int size) {
  final out = Uint8List(size);
  var i = 0;

  while (i < size) {
    // A u32 can sample 5 characters ((2^6) * 5), with 2 bits leftover.
    int r = random.nextInt(_u32);

    var k = 0;
    while (k < 5 && i < size) {
      // Sample a character randomly from the 64 characters.
      out[i++] = _alphabytes[r & 63];
      r >>= 6;
      k++;
    }
  }

  return String.fromCharCodes(out);
}

/// Generates a cryptographically secure, URL-safe random ID for values that may
/// be user-visible, persisted, synced, or treated as unguessable by callers.
///
/// Use this for document IDs and other public identifiers.
/// Default: 21 chars, about 126 bits of entropy.
String generateSecureId([int size = 21]) =>
    _generateRandomId(_secureRandom, size);

/// Generates a URL-safe random ID from a non-cryptographic PRNG.
///
/// Use this only for ephemeral internal identifiers that need local uniqueness
/// but do not need to be hard to guess, such as observer IDs or request
/// correlation IDs. Do not use it for document IDs, access tokens, or other
/// public identifiers where unpredictability matters.
String generateFastId([int size = 21]) => _generateRandomId(_fastRandom, size);
