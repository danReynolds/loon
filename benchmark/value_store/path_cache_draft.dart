import 'dart:collection';

// Experimental immutable path metadata. Never retains a store node or value.
class ParsedStorePath {
  final List<String> segments;
  final int accountedBytes;

  factory ParsedStorePath(String path) {
    final segments = _splitPath(path);
    return ParsedStorePath._(List.unmodifiable(segments),
        128 + path.length * 4 + segments.length * 48);
  }

  ParsedStorePath._(this.segments, this.accountedBytes);

  T? read<T>(Map root) {
    Map node = root;
    for (var i = 0; i < segments.length - 1; i++) {
      final Map? child = node[segments[i]];
      if (child == null) return null;
      node = child;
    }
    return node['__values']?[segments.last];
  }

  // Budget estimate, not a physical heap ceiling or exact VM object sizes.
  // Charges for the key, segment strings, list slots and map/object overhead;
  // keep entry/key limits too, and verify actual retention separately.
  static List<String> _splitPath(String path) {
    final parts = <String>[];
    var start = 0;
    for (var i = 0; i < path.length - 1; i++) {
      if (path.codeUnitAt(i) == 95 && path.codeUnitAt(i + 1) == 95) {
        parts.add(path.substring(start, i));
        start = i + 2;
        i++;
      }
    }
    parts.add(path.substring(start));
    return parts;
  }
}

abstract class PathPlanCache {
  ParsedStorePath? lookup(String path);
  int get length;
  int get accountedBytes;
  void clear();
}

class BoundedPathCache implements PathPlanCache {
  final int maxBytes;
  final int maxEntries;
  final int maxPathLength;
  final _entries = <String, _PathCacheEntry>{};
  final _order = LinkedList<_PathCacheEntry>();
  @override
  int accountedBytes = 0;

  BoundedPathCache({
    this.maxBytes = 512 * 1024,
    this.maxEntries = 1024,
    this.maxPathLength = 512,
  });

  @override
  int get length => _entries.length;

  @override
  ParsedStorePath? lookup(String path) {
    if (path.length > maxPathLength) return null;
    final hit = _entries[path];
    if (hit != null) {
      hit.unlink();
      _order.add(hit);
      return hit.parsed;
    }
    final parsed = ParsedStorePath(path);
    if (parsed.accountedBytes > maxBytes || maxEntries < 1) return null;
    while (_entries.isNotEmpty &&
        (_entries.length >= maxEntries ||
            accountedBytes + parsed.accountedBytes > maxBytes)) {
      final oldest = _order.first;
      oldest.unlink();
      _entries.remove(oldest.path);
      accountedBytes -= oldest.parsed.accountedBytes;
    }
    final entry = _PathCacheEntry(path, parsed);
    _entries[path] = entry;
    _order.add(entry);
    accountedBytes += parsed.accountedBytes;
    return parsed;
  }

  @override
  void clear() {
    _entries.clear();
    _order.clear();
    accountedBytes = 0;
  }
}

final class _PathCacheEntry extends LinkedListEntry<_PathCacheEntry> {
  final String path;
  final ParsedStorePath parsed;
  _PathCacheEntry(this.path, this.parsed);
}

// Admit only after two consecutive uses. The first access still takes the
// ordinary scanner, avoiding parsed-list allocation for a one-off path.
class RecentPathCache implements PathPlanCache {
  final int maxPathLength;
  String? _path;
  ParsedStorePath? _parsed;

  RecentPathCache({this.maxPathLength = 512});

  @override
  ParsedStorePath? lookup(String path) {
    if (path.length > maxPathLength) {
      clear();
      return null;
    }
    if (path == _path) return _parsed ??= ParsedStorePath(path);
    _path = path;
    _parsed = null;
    return null;
  }

  @override
  int get length => _path == null ? 0 : 1;
  @override
  int get accountedBytes =>
      _parsed?.accountedBytes ?? (_path == null ? 0 : 64 + _path!.length * 2);

  @override
  void clear() {
    _path = null;
    _parsed = null;
  }
}

class PathOwner {
  final String path;
  ParsedStorePath? parsed;
  PathOwner(this.path);
}
