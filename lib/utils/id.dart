import 'dart:math';
import 'dart:typed_data';

// 64-characters (2^6)
const String _alphabet =
    '_-0123456789abcdefghijklmnopqrstuvwxyzABCDEFGHIJKLMNOPQRSTUVWXYZ';
final Uint8List _alphabytes = Uint8List.fromList(_alphabet.codeUnits);
const int _u32 = 0x100000000; // 2^32

final Random _secureRandom = Random.secure();
final Random _processLocalRandom = Random();

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

/// Generates a cryptographically secure, URL-safe random ID.
/// Default: 21 chars ≈ 126 bits of entropy.
String generateSecureId([int size = 21]) =>
    _generateRandomId(_secureRandom, size);

/// Backward-compatible alias for [generateSecureId].
String generateId([int size = 21]) => generateSecureId(size);

/// Generates a URL-safe random ID from a non-cryptographic PRNG, for internal
/// identifiers that only need process-local uniqueness.
/// Drawing from the OS CSPRNG via [generateSecureId] is needless overhead there.
String generateProcessLocalId([int size = 21]) =>
    _generateRandomId(_processLocalRandom, size);
