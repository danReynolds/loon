import 'dart:math';

/// Helpers for the store property tests, which check random write/delete sequences against
/// a flat map used as an oracle. Paths are drawn from a small alphabet so that they collide
/// and share prefixes, which is where the tree-restructuring edge cases live.

const pathDelimiter = '__';
const pathAlphabet = ['a', 'b', 'c'];

/// A random path of 1 to 3 segments over [pathAlphabet].
String randomPath(Random r) {
  final depth = 1 + r.nextInt(3);
  return List.generate(
          depth, (_) => pathAlphabet[r.nextInt(pathAlphabet.length)])
      .join(pathDelimiter);
}

/// All non-empty paths of depth 1 and 2: a fixed grid of query points.
final pathGrid = <String>[
  for (final a in pathAlphabet) ...[
    a,
    for (final b in pathAlphabet) '$a$pathDelimiter$b',
  ],
];

/// Whether [key] is at or below [path] in the tree.
bool isAtOrUnder(String key, String path) =>
    path.isEmpty || key == path || key.startsWith('$path$pathDelimiter');

/// The parent path of [path], or the empty string for a top-level path.
String parentPath(String path) {
  final i = path.lastIndexOf(pathDelimiter);
  return i == -1 ? '' : path.substring(0, i);
}

/// The last segment of [path].
String lastSegment(String path) {
  final i = path.lastIndexOf(pathDelimiter);
  return i == -1 ? path : path.substring(i + pathDelimiter.length);
}
