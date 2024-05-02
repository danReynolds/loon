part of loon;

/// An indexed value store is a tree structure that takes a path and indexes its value into the tree as a
/// key of its parent path, enabling efficient access to all values of the parent path.
///
/// Ex. In this example, the parent path `users__2__messages` indexes the value 'Test' by its key `1`.
///
/// ```dart
/// final store = IndexedValueStore<String>();
/// store.write('users__2__messages__1', 'Test');
/// store.write('users__2__messages__2', 'Test again');
/// {
///   users: {
///     2: {
///       messages: {
///         __values: {
///           1: 'Test',
///           2: 'Test again',
///         }
///       }
///     }
///   }
/// }
/// ```
///
/// All values of the given path can then be retrieved as shown below:
///
/// ```dart
/// final values = store.getAll('users__2__messages');
/// {
///   1: 'Test',
///   2: 'Test again',
/// }
/// ```
///
/// This is used in modeling collections, which index their documents by key and require
/// efficient access to all of their values.
class IndexedValueStore<T> {
  final Map _store = {};

  static const _delimiter = '__';
  static const _values = '__values';

  /// Returns the node at the given path.
  Map? _getNode(Map node, List<String> segments, int index) {
    if (segments.isEmpty) {
      return null;
    }

    if (index < segments.length - 1) {
      final Map? child = node[segments[index]];
      if (child == null) {
        return null;
      }

      return _getNode(child, segments, index + 1);
    }

    return node;
  }

  /// Merges the values and child keys of the given other node into the given node.
  Map _mergeNode(Map node, Map otherNode) {
    for (final entry in otherNode.entries) {
      final key = entry.key;

      if (key == _values) {
        if (node.containsKey(_values)) {
          node[_values] = {
            ...(node[_values] as Map),
            ...entry.value,
          };
        } else {
          node[_values] = entry.value;
        }
      } else if (node.containsKey(key)) {
        node[key] = _mergeNode(node[key], otherNode[key]);
      } else {
        node[key] = entry.value;
      }
    }

    return node;
  }

  /// Writes an empty node at the given path if a node does not already exist.
  Map _touch(Map node, List<String> segments, int index) {
    final child = node[segments[index]] ??= {};

    if (index < segments.length - 1) {
      return _touch(child, segments, index + 1);
    }

    return child;
  }

  Map touch(String path) {
    return _touch(_store, path.split(_delimiter), 0);
  }

  /// Returns the value for the given path.
  T? get(String path) {
    final segments = path.split(_delimiter);
    return _getNode(_store, segments, 0)?[_values]?[segments.last];
  }

  T? _getNearest(Map node, List<String> segments, int index) {
    if (index < segments.length - 1) {
      final segment = segments[index];
      final Map? child = node[segment];
      if (child == null) {
        return null;
      }

      final value = _getNearest(child, segments, index + 1);

      if (value != null) {
        return value;
      }

      return node[_values][segment];
    }

    return node[_values][segments[index]];
  }

  /// Returns the nearest value along the given path, beginning at the full path
  /// and then attempting to find a non-null value for any parent node moving up the tree.
  T? getNearest(String path) {
    return _getNearest(_store, path.split(_delimiter), 0);
  }

  /// Returns a map of all values that are immediate children of the given path.
  Map<String, T>? getAll(String path) {
    return _getNode(_store, path.split(_delimiter), 0)?[_values];
  }

  void _write(Map node, List<String> segments, int index, T value) {
    if (index < segments.length - 1) {
      final child = node[segments[index]] ??= {};
      return _write(child, segments, index + 1, value);
    }

    final values = node[_values] ??= <String, T>{};
    values[segments.last] = value;
  }

  /// Writes the value at the given path.
  T write(String path, T value) {
    _write(_store, path.split(_delimiter), 0, value);
    return value;
  }

  // Deletes the path from the store. Returns whether the node is empty after the removal.
  bool _delete(Map node, List<String> segments, int index) {
    if (index < segments.length - 1) {
      final segment = segments[index];
      final Map? child = node[segment];

      if (child == null) {
        return false;
      }

      if (_delete(child, segments, index + 1) && node.length == 1) {
        if (index == 0) {
          node.remove(segment);
        }

        return true;
      }
      return false;
    }

    final segment = segments.last;
    node.remove(segment);

    if (node.containsKey(_values)) {
      final Map values = node[_values];
      values.remove(segment);

      if (values.isEmpty) {
        node.remove(_values);
      }
    }

    return node.isEmpty;
  }

  void delete(String path) {
    _delete(_store, path.split(_delimiter), 0);
  }

  /// Returns whether the store has a value for the given path.
  bool has(String path) {
    return get(path) != null;
  }

  /// Returns whether the store has any values for the given path.
  bool hasAny(String path) {
    return getAll(path)?.isNotEmpty ?? false;
  }

  void clear() {
    _store.clear();
  }

  bool get isEmpty {
    return _store.isEmpty;
  }

  Map inspect() {
    return _store;
  }

  Map<String, T> _extract(
    Map node, [
    String path = '',
    Map<String, T> index = const {},
  ]) {
    if (node.containsKey(_values)) {
      for (final entry in node[_values].entries) {
        index["${path}__${entry.key}"] = entry.value;
      }
    }

    for (final key in node.keys) {
      if (key != _values) {
        _extract(node, "${path}__$key", index);
      }
    }

    return index;
  }

  /// Extracts all values from the store into a set of flat key-value pairs of paths to values.
  Map<String, T> extract() {
    return _extract(_store);
  }

  /// Similar to [extract], extracts all values from the store into a flat key-value pairs beginning
  /// at the given path.
  Map<String, T> extractPath(String path) {
    final node = _getNode(_store, path.split(_delimiter), 0);

    if (node == null) {
      return {};
    }

    return _extract(node, path);
  }

  /// Removes the subtree at the given [path] of the other provided [IndexedValueStore] and recursively
  /// merges it onto this store at the given path.
  void graft(
    IndexedValueStore other,
    String path,
  ) {
    final otherNode = _getNode(other._store, path.split(_delimiter), 0);
    if (otherNode == null || otherNode.isEmpty) {
      return;
    }
    other.delete(path);

    final node = _getNode(_store, path.split(_delimiter), 0) ?? touch(path);

    _mergeNode(node, otherNode);
  }
}
