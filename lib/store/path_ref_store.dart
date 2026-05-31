part of '../loon.dart';

/// The path ref store is a tree structure that maintains a ref count of the number of times a path has been added to the tree.
///
/// Ex.
///
/// ```dart
/// final store = PathRefStore();
/// store.inc('posts__1');
/// store.inc('posts__1__comments__2');
/// store.inc('posts__2');
/// {
///   "posts": {
///     "__ref": 3,
///     "1": {
///       "__ref": 2,
///       "comments": {
///         "__ref": 1,
///         "2": 1,
///       },
///     },
///     "2": 1,
///   },
/// }
/// ```
///
/// The path ref store is used to create the dependency graphs of an [ObservableQuery] so that
/// it is efficient to check whether a query depends on a deleted path, as determined by
/// the presence of the path in the query's associated ref store.
class PathRefStore {
  final Map<String, dynamic> _store = {};

  static const delimiter = '__';
  static const _refKey = '__ref';

  void _inc(
    Map node,
    List<String> segments, [
    int index = 0,
  ]) {
    final segment = segments[index];

    node[_refKey] ??= 0;
    node[_refKey]++;

    if (index < segments.length - 1) {
      if (node[segment] is int) {
        node[segment] = {
          _refKey: node[segment],
        };
      } else if (node[segment] == null) {
        node[segment] = <String, dynamic>{
          _refKey: 0,
        };
      }

      return _inc(node[segment], segments, index + 1);
    }

    // If the child node already has a ref count, then just increment it.
    if (node[segment] is int) {
      node[segment]++;
      // If the child node is a map with deeper dependencies, then increment its ref count key.
    } else if (node[segment] is Map) {
      node[segment][_refKey]++;
      // Otherwise, the child node does not exist yet and its ref count is initialized.
    } else {
      node[segment] = 1;
    }
  }

  /// Increments the ref count to the given path.
  void inc(String path) {
    _inc(_store, path.split(delimiter));
  }

  int _refCount(Object? value) {
    if (value is int) {
      return value;
    }
    if (value is Map) {
      return value[_refKey] as int? ?? 0;
    }
    return 0;
  }

  int _directRefCount(Map node) {
    final refCount = node[_refKey] as int? ?? 0;
    final descendantRefCount = node.entries
        .where((entry) => entry.key != _refKey)
        .fold<int>(0, (sum, entry) => sum + _refCount(entry.value));

    return refCount - descendantRefCount;
  }

  bool _hasDirectRef(Map? node, List<String> segments, [int index = 0]) {
    final segment = segments[index];
    if (node == null) {
      return false;
    }

    if (index < segments.length - 1) {
      final child = node[segment];
      if (child is! Map) {
        return false;
      }

      return _hasDirectRef(child, segments, index + 1);
    }

    final child = node[segment];
    if (child is int) {
      return child > 0;
    }
    if (child is Map) {
      return _directRefCount(child) > 0;
    }

    return false;
  }

  bool _dec(
    Map? node,
    List<String> segments, [
    int index = 0,
  ]) {
    final segment = segments[index];

    if (node == null) {
      return true;
    }

    if (node[_refKey] == 1) {
      if (index == 0) {
        node.clear();
      }
      return true;
    }

    if (index < segments.length - 1) {
      if (_dec(node[segment], segments, index + 1)) {
        node.remove(segment);
      }
      node[_refKey]--;
      return false;
    }

    // If the child node is an int ref count, then decrement it.
    if (node[segment] is int) {
      // If this is the last reference to the child node, then mark it for removal.
      if (node[segment] == 1) {
        node.remove(segment);
      } else {
        node[segment]--;
      }
    } else if (node[segment] is Map) {
      final Map child = node[segment];
      if (child[_refKey] == 1) {
        node.remove(segment);
      } else {
        child[_refKey]--;
      }
    }

    node[_refKey]--;

    return false;
  }

  /// Decrements the ref count to the node at the given path, removing it if it was the last reference to the node.
  void dec(String path) {
    final segments = path.split(delimiter);
    // `_dec` assumes the target path has a direct ref. `has` is broader: it is
    // also true when only a descendant is live, which must not decrement this
    // path.
    if (!_hasDirectRef(_store, segments)) {
      return;
    }
    _dec(_store, segments);
  }

  bool _has(Map? node, List<String> segments, [int index = 0]) {
    final segment = segments[index];
    if (node == null) {
      return false;
    }

    if (index < segments.length - 1) {
      final child = node[segment];
      if (child == null || child is! Map) {
        return false;
      }

      return _has(child, segments, index + 1);
    }

    return node.containsKey(segment);
  }

  /// Returns whether the path or any descendant path exists in the store.
  ///
  /// Example:
  /// ```dart
  /// final refStore = PathRefStore();
  /// refStore.inc('users__1__posts__2');
  /// refStore.has('users__1__posts__2') // true
  /// refStore.has('users__1') // true
  ///
  /// ```
  bool has(String path) {
    return _has(_store, path.split(delimiter));
  }

  bool get isEmpty {
    return _store.isEmpty;
  }

  void clear() {
    _store.clear();
  }

  Map inspect() {
    return _store;
  }
}
