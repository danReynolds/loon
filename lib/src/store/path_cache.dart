part of 'store.dart';

/// A cache of the last path resolved in a store, the index at which its final segment starts, and
/// the parent node that owns that segment.
class _PathCache {
  final String path;
  final int lastSegmentStart;
  final Map lastParentNode;

  _PathCache(this.path, this.lastSegmentStart, this.lastParentNode);

  /// Whether [other] has the same parent as [path]. Their segments before the final one are
  /// identical, so they split the same way up to it.
  @pragma('vm:prefer-inline')
  bool isMatch(String other) {
    if (identical(other, path)) {
      return true;
    }

    final start = lastSegmentStart;
    if (other.length < start) {
      return false;
    }
    for (var i = 0; i < start; i++) {
      if (other.codeUnitAt(i) != path.codeUnitAt(i)) {
        return false;
      }
    }
    return _nextStoreDelimiter(other, start) < 0;
  }
}
