part of 'store.dart';

/// Finds the next `__` separator. Specializing the fixed two-character delimiter
/// avoids the general substring search on every segment of a store path.
/// Callers advance past both characters to preserve non-overlapping matches.
@pragma('vm:prefer-inline')
int _nextStoreDelimiter(String path, int start) {
  const underscore = 0x5f;
  for (var i = start; i < path.length - 1; i++) {
    if (path.codeUnitAt(i) == underscore &&
        path.codeUnitAt(i + 1) == underscore) {
      return i;
    }
  }
  return -1;
}

/// Returns the index at which the final segment of [path] begins. Delimiters are matched
/// left to right without overlapping, as [String.split] does, so `a___b` ends in `_b`.
int _lastSegmentStart(String path) {
  const delimiter = _BaseValueStore.delimiter;
  var start = 0;
  while (true) {
    final end = _nextStoreDelimiter(path, start);
    if (end < 0) return start;
    start = end + delimiter.length;
  }
}

/// Splits [path] into its parent path and final segment, materializing only those two strings.
(String, String) splitReferencePath(String path) {
  final start = _lastSegmentStart(path);
  return start == 0
      ? ('', path)
      : (
          path.substring(0, start - _BaseValueStore.delimiter.length),
          path.substring(start),
        );
}
