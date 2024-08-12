part of loon;

/// A value store is a tree structure that takes a path and indexes its value into the tree as a
/// key of its parent path, enabling efficient access to all values of the parent path.
///
/// Ex. In this example, the parent path `users__2__messages` indexes the value 'Test' by its key `1`.
///
/// ```dart
/// final store = ValueStore<String>();
/// store.write('users__2__messages__1', 'Test');
/// store.write('users__2__messages__2', 'Test again');
///
/// print(store.inspect());
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
/// final values = store.getChildValues('users__2__messages');
///
/// print(values);
/// {
///   1: 'Test',
///   2: 'Test again',
/// }
/// ```
/// The [ValueStore] is the data structure used throughout the library for storing collections of documents.
class ValueStore<T> {
  Map _store = {};

  static const _values = '__values';
  static const delimiter = '__';

  ValueStore([Map? store]) {
    if (store != null) {
      _store = store;
    }
  }

  static ValueStore fromJson(Json json) {
    return ValueStore(json);
  }

  /// Returns the node at the given path.
  Map? _getNode(Map? node, List<String> segments, int index) {
    if (node == null || index == segments.length) {
      return node;
    }

    final segment = segments[index];
    if (segment.isEmpty) {
      return node;
    }

    return _getNode(node[segment], segments, index + 1);
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
    if (segments.isEmpty) {
      return node;
    }

    final child = node[segments[index]] ??= {};

    if (index < segments.length - 1) {
      return _touch(child, segments, index + 1);
    }

    return child;
  }

  Map touch(String path) {
    return _touch(_store, path.split(delimiter), 0);
  }

  /// Returns the value for the given path.
  T? get(String path) {
    if (_store.isEmpty) {
      return null;
    }

    final segments = path.split(delimiter);
    return _getNode(
      _store,
      segments.isEmpty ? segments : segments.sublist(0, segments.length - 1),
      0,
    )?[_values]?[segments.last];
  }

  (String, T)? _getNearest(
    Map? node,
    List<String> segments,
    int index,
    T? value,
  ) {
    if (node == null) {
      return null;
    }

    final segment = segments[index];
    if (index < segments.length - 1) {
      final result = _getNearest(node[segment], segments, index + 1, value);
      if (result != null) {
        return result;
      }
    }

    final nodeValue = node[_values]?[segment];
    if (nodeValue != null && (value == null || nodeValue == value)) {
      return (segments.sublist(0, index + 1).join(delimiter), nodeValue);
    }

    return null;
  }

  /// Returns the nearest path/value pair that has a matching value along the given path, beginning at the full path
  /// and then attempting to find the value at any parent node moving up the tree. If no value is provided, it returns
  /// the nearest non-null path.
  (String, T)? getNearest(String path, [T? value]) {
    return _getNearest(_store, path.split(delimiter), 0, value);
  }

  /// Returns a map of all values that are immediate children of the given path.
  Map<String, T>? getChildValues(String path) {
    return _getNode(_store, path.split(delimiter), 0)?[_values];
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
    _write(_store, path.split(delimiter), 0, value);
    return value;
  }

  bool _delete(
    Map node,
    List<String> segments,
    int index, [
    bool recursive = true,
  ]) {
    if (index < segments.length - 1) {
      final segment = segments[index];
      final Map? child = node[segment];

      if (child == null) {
        return false;
      }

      if (_delete(child, segments, index + 1, recursive)) {
        if (node.length == 1) {
          if (index == 0) {
            node.remove(segment);
          }

          return true;
        }

        node.remove(segment);
      }
      return false;
    }

    final segment = segments.last;
    if (recursive) {
      node.remove(segment);
    } else {
      final Map? child = node[segment];
      if (child != null) {
        if (child.keys.length == 1 && child.containsKey(_values)) {
          node.remove(segment);
        } else {
          child.remove(_values);
        }
      }
    }

    if (node.containsKey(_values)) {
      final Map values = node[_values];
      values.remove(segment);

      if (values.isEmpty) {
        node.remove(_values);
      }
    }

    return node.isEmpty;
  }

  /// Deletes the values at the given path and optionally its subtree from the store.
  void delete(
    String path, {
    /// Whether the data in the subtree under the given path should also be deleted.
    /// If false, only the values at the given path are deleted and the subtree is maintained.
    bool recursive = true,
  }) {
    if (path.isEmpty) {
      _store = {};
      return;
    }

    _delete(_store, path.split(delimiter), 0, recursive);
  }

  /// Returns whether the store has a value for the given path.
  bool hasValue(String path) {
    return get(path) != null;
  }

  /// Returns whether the store has any child values under the given path.
  bool hasChildValues(String path) {
    return getChildValues(path)?.isNotEmpty ?? false;
  }

  /// Returns whether the store contains the given path either as a value or a path
  /// to subtree values.
  bool hasPath(String path) {
    if (path.isEmpty) {
      return true;
    }

    return hasValue(path) || _getNode(_store, path.split(delimiter), 0) != null;
  }

  void clear() {
    _store = {};
  }

  bool get isEmpty {
    return _store.isEmpty;
  }

  /// Returns a map of the values in the store by path.
  Map inspect() {
    return _store;
  }

  /// Grafts the data under the given path from the other store into this store. Returns
  /// whether the other store's node can be deleted after grafted.
  bool _graft(Map node, Map? otherNode, List<String> segments, int index) {
    if (otherNode == null) {
      return false;
    }

    final segment = segments[index];

    if (index < segments.length - 1) {
      final Map? otherChildNode = otherNode[segment];

      if (otherChildNode == null) {
        return false;
      }

      final Map childNode = node[segment] ??= {};

      if (_graft(childNode, otherChildNode, segments, index + 1)) {
        if (otherNode.length == 1) {
          if (index == 0) {
            otherNode.remove(segment);
          }
          return true;
        }
      }

      return false;
    }

    if (otherNode.containsKey(_values)) {
      final otherValues = otherNode[_values];

      if (otherValues.containsKey(segment)) {
        final value = otherValues.remove(segment);

        final values = node[_values] ??= {};
        values[segment] = value;
      }

      if (otherNode[_values].isEmpty) {
        otherNode.remove(_values);
      }
    }

    final Map? otherChildNode = otherNode[segment];
    if (otherChildNode == null) {
      return otherNode.isEmpty;
    }

    otherNode.remove(segment);

    final Map childNode = node[segment] ??= {};

    _mergeNode(childNode, otherChildNode);

    return otherNode.isEmpty;
  }

  /// Removes the subtree at the given [path] of the other provided [ValueStore] and recursively
  /// merges it onto this store at the given path.
  void graft(
    ValueStore<T> other, [
    String? path = '',
  ]) {
    if (path == null || path.isEmpty) {
      final otherNode = other._store;
      other.clear();
      _mergeNode(_store, otherNode);
    } else {
      _graft(_store, other._store, path.split(delimiter), 0);
    }
  }

  Map<String, T> _extractValues(
    Map? node,
    Map<String, T> values,
    String path,
  ) {
    if (node == null) {
      return values;
    }

    if (node.containsKey(_values)) {
      for (final entry in node[_values].entries) {
        final key = path.isEmpty ? entry.key : "$path$delimiter${entry.key}";
        values[key] = entry.value;
      }
    }

    for (final key in node.keys) {
      if (key != _values) {
        final childPath = path.isEmpty ? key : "$path$delimiter$key";
        _extractValues(node[key], values, childPath);
      }
    }

    return values;
  }

  /// Extracts all values under the given path into a set of flat key-value pairs of paths to values.
  Map<String, T> extractValues([String path = '']) {
    if (path.isEmpty) {
      return _extractValues(_store, {}, path);
    }

    final Map<String, T> values = {};
    final segments = path.split(delimiter);
    final lastSegment = segments.removeLast();

    final parentNode = _getNode(_store, segments, 0);

    if (parentNode == null) {
      return values;
    }

    if (parentNode[_values]?.containsKey(lastSegment) ?? false) {
      values[path] = parentNode[_values][lastSegment];
    }

    return _extractValues(parentNode[lastSegment], values, path);
  }
}
