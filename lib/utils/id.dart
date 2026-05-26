import 'dart:math';
import 'dart:typed_data';

// Alphanumeric only (62 characters). Generated IDs are used as `__`-delimited
// path segments throughout the store (document paths, observer value keys), so
// they must never contain that delimiter. The previous alphabet included `_`,
// which meant a random ID could contain `__` and be parsed as a segment
// boundary — misplacing the value deeper in the store than reads/invalidations
// expect (e.g. an observer value never getting invalidated, or an auto-id
// document being invisible to its collection). Restricting to [0-9A-Za-z]
// removes the delimiter character entirely, so no ID can introduce a boundary.
const String _alphabet =
    '0123456789abcdefghijklmnopqrstuvwxyzABCDEFGHIJKLMNOPQRSTUVWXYZ';
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
      final index = r & 63;
      r >>= 6;
      k++;
      // The 6-bit sample spans 0-63; reject the values past the 62-char
      // alphabet so every character is sampled uniformly.
      if (index < _alphabytes.length) {
        out[i++] = _alphabytes[index];
      }
    }
  }

  return String.fromCharCodes(out);
}

/// Generates a cryptographically secure, URL-safe random ID for values that may
/// be user-visible, persisted, synced, or treated as unguessable by callers.
///
/// Use this for document IDs and other public identifiers.
/// Default: 21 chars, about 125 bits of entropy.
String generateSecureId([int size = 21]) =>
    _generateRandomId(_secureRandom, size);

/// Generates a URL-safe random ID from a non-cryptographic PRNG.
///
/// Use this only for ephemeral internal identifiers that need local uniqueness
/// but do not need to be hard to guess, such as observer IDs or request
/// correlation IDs. Do not use it for document IDs, access tokens, or other
/// public identifiers where unpredictability matters.
String generateFastId([int size = 21]) => _generateRandomId(_fastRandom, size);
