part of loon;

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
      // If this is the last reference to the child node, then remove the ref key from the child,
      // marking that it is now purely a transient node.
      if (node[segment][_refKey] == 1) {
        return true;
      } else {
        node[segment][_refKey]--;
      }
    }

    node[_refKey]--;

    return false;
  }

  /// Decrements the ref count to the node at the given path, removing it if it was the last reference to the node.
  void dec(String path) {
    _dec(_store, path.split(delimiter));
  }

  bool _has(Map? node, List<String> segments, [int index = 0]) {
    final segment = segments[index];
    if (node == null) {
      return false;
    }

    if (index < segments.length - 1) {
      return _has(node[segment], segments, index + 1);
    }

    return node.containsKey(segment);
  }

  /// Returns whether the path exists in the store.
  ///
  /// Example:
  /// ```dart
  /// final refStore = PathRefStore();
  /// refStore.inc('users__1__posts__2');
  /// refStore.has('users__1__posts__2') // true
  /// refStore.has('users__1') // false
  /// refStore.hasPath('users__1') // true
  ///
  /// ```
  bool has(String path) {
    return _has(_store, path.split(delimiter));
  }

  void clear() {
    _store.clear();
  }

  Map inspect() {
    return _store;
  }
}
