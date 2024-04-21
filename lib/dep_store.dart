part of loon;

class DepStore {
  final _store = {};

  static const delimiter = '__';
  static const _refKey = '__ref';

  void _inc(
    Map node,
    List<String> segments, [
    int index = 0,
  ]) {
    final segment = segments[index];

    if (index < segments.length - 1) {
      final child = node[segment];

      // If this is the first deeper dependency of an existing terminal node,
      // then re-initialize it as a map.
      if (child is int) {
        node[segment] = {
          _refKey: node[segment],
        };
        // Otherwise, if the child node does not exist yet, initialize it as an empty
        // transient node.
      } else if (child == null) {
        node[segment] = {};
      }

      return _inc(node[segment], segments, index + 1);
    }

    // If the node already has a ref count, then just increment it.
    if (node[segment] is int) {
      node[segment]++;
      // If the node is a map with deeper dependencies, then increment its ref count key.
    } else if (node[segment] is Map) {
      if (node[segment].containsKey(_refKey)) {
        node[segment][_refKey]++;
      } else {
        node[segment][_refKey] = 1;
      }
      // Otherwise, the node does not exist yet and its ref count is initialized.
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

    if (index < segments.length - 1) {
      if (_dec(node[segment], segments, index + 1)) {
        // If the child node is marked for removal after decrementing it, then if the current node
        // is not a dependency itself (as denoted by not having a ref count) and it has no
        // other deeper dependencies, mark it for removal as well.
        if (!node.containsKey(_refKey) && node.length == 1) {
          // If the first child of the path is marked for removal, then the root node removes the entire
          // path subtree.
          if (index == 0) {
            node.remove(segment);
          }
          return true;
        }

        node.remove(segment);
      }
      return false;
    }

    // If the child node is an int ref count, then decrement it.
    if (node[segment] is int) {
      // If this is the last reference to the child node, then mark it for removal
      // and mark the current node for removal as well if this was its only child
      // and it is not a ref itself (as denoted by the node having no other keys).
      if (node[segment] == 1) {
        if (node.length == 1) {
          return true;
        }
        node.remove(segment);
        return false;
      }
      node[segment]--;
      // If the child node is a map and has references to deeper nodes, then decrement
      // its ref key if it has one, and return false since it must retain the deeper nodes
      // and is not eligible for removal.
    } else if (node[segment].containsKey(_refKey)) {
      // If this is the last reference to the child node, then remove the ref key from the child,
      // marking that it is now purely a transient node.
      if (node[segment][_refKey] == 1) {
        node[segment].remove(_refKey);
      } else {
        node[segment][_refKey]--;
      }
    }

    return false;
  }

  /// Decrements the ref count to the node at the given path, removing it if it was the last reference to the node.
  void dec(String path) {
    _dec(_store, path.split(delimiter));
  }

  bool _has(
    Map? node,
    List<String> segments, [
    int index = 0,
  ]) {
    final segment = segments[index];
    if (node == null) {
      return false;
    }

    if (index < segments.length - 1) {
      return _has(node[segment], segments, index + 1);
    }

    if (node[segment] is Map) {
      return node[segment].containsKey(_refKey);
    }

    return true;
  }

  /// Returns whether the path has been added as a dependency in the store.
  bool has(String path) {
    return _has(_store, path.split(delimiter));
  }

  bool _hasPath(Map? node, List<String> segments, [int index = 0]) {
    final segment = segments[index];
    if (node == null) {
      return false;
    }

    if (index < segments.length - 1) {
      return _hasPath(node[segment], segments, index + 1);
    }

    return node.containsKey(segment);
  }

  /// Returns whether the path exists in the store, returning true even if the path is not
  /// a terminal dependency itself and has no ref count in the store but is just a transient
  /// path to a deeper dependency.
  ///
  /// Example:
  /// ```dart
  /// final depStore = DepStore();
  /// depStore.inc('users__1__posts__2');
  /// depStore.has('users__1__posts__2') // true
  /// depStore.has('users__1') // false
  /// depStore.hasPath('users__1') // true
  ///
  /// ```
  bool hasPath(String path) {
    return _hasPath(_store, path.split(delimiter));
  }

  Map inspect() {
    return _store;
  }
}
