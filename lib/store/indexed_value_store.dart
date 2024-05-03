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
  Map _store = {};

  static const _delimiter = '__';
  static const _values = '__values';

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
    return _getNode(
      _store,
      segments.isEmpty ? segments : segments.sublist(0, segments.length - 1),
      0,
    )?[_values][segments.last];
  }

  T? _getNearest(Map? node, List<String> segments, int index) {
    if (node == null) {
      return null;
    }

    if (index < segments.length - 1) {
      final segment = segments[index];

      final value = _getNearest(node[segment], segments, index + 1);
      if (value != null) {
        return value;
      }

      return node[_values]?[segment];
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

      if (_delete(child, segments, index + 1)) {
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
    if (path.isEmpty) {
      _store = {};
      return;
    }

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
    _store = {};
  }

  bool get isEmpty {
    return _store.isEmpty;
  }

  Map inspect() {
    return _store;
  }

  Map<String, T> _extract(
    Map node,
    Map<String, T> index, [
    String path = '',
  ]) {
    if (node.containsKey(_values)) {
      for (final entry in node[_values].entries) {
        final key = path.isEmpty ? entry.key : "${path}__${entry.key}";
        index[key] = entry.value;
      }
    }

    for (final key in node.keys) {
      if (key != _values) {
        final childPath = path.isEmpty ? key : "${path}__$key";
        _extract(node[key], index, childPath);
      }
    }

    return index;
  }

  /// Extracts all values from the store into a set of flat key-value pairs of paths to values.
  Map<String, T> extract() {
    return _extract(_store, {});
  }

  /// Removes the subtree at the given [path] of the other provided [IndexedValueStore] and recursively
  /// merges it onto this store at the given path.
  void graft(
    IndexedValueStore other, [
    String path = '',
  ]) {
    if (path.isEmpty) {
      final otherNode = other._store;

      other.clear();

      _mergeNode(_store, otherNode);
    } else {
      // Initialize the nodes of the given path in this store.
      touch(path);

      final segments = path.split(_delimiter);
      // Remove the last segment from the path so that resolved node is the
      // parent node of the node corresponding to the final path segment. This is
      // necessary for also grafting the final node's value from the parent node.
      final lastSegment = segments.removeLast();

      final node = _getNode(_store, segments, 0)!;
      final otherNode = _getNode(other._store, segments, 0);

      if (otherNode == null || otherNode.isEmpty) {
        return;
      }

      if (otherNode[_values]?.containsKey(lastSegment) ?? false) {
        node[_values] ??= {};
        node[_values][lastSegment] = otherNode[_values][lastSegment];
      }

      final child = node[lastSegment];
      final otherChild = otherNode[lastSegment];

      if (otherChild == null) {
        return;
      }

      _mergeNode(child, otherChild);
    }
  }

  /// Hydrates a store from serialized data.
  void hydrate(Json data) {
    _store = data;
  }
}

/// A variant of the [IndexedValueStore] that additionally keeps a ref count of each
/// distinct value in a given path's values.
class IndexedRefValueStore<T> extends IndexedValueStore<T> {
  static const _refs = '__refs';

  int _getRefCount(Map? node, List<String> segments, int index, T value) {
    if (node == null || segments.isEmpty) {
      return 0;
    }

    if (index < segments.length) {
      return _getRefCount(node[segments[index]], segments, index + 1, value);
    }

    return node[_refs]?[value] ?? 0;
  }

  /// Returns the ref count for the value at the given path.
  int getRefCount(String path, T value) {
    return _getRefCount(
      _store,
      path.split(IndexedValueStore._delimiter),
      0,
      value,
    );
  }

  @override
  Map _mergeNode(Map node, Map otherNode) {
    final result = super._mergeNode(node, otherNode);

    final otherValues = otherNode[IndexedValueStore._values];
    if (otherValues != null) {
      node[_refs] ??= {};

      for (final value in otherValues) {
        node[_refs][value] ??= 0;
        node[_refs][value]++;
      }
    }

    return result;
  }

  @override
  void _write(Map node, List<String> segments, int index, T value) {
    super._write(node, segments, index, value);

    if (index == segments.length - 1) {
      final refs = node[_refs] ??= <T, int>{};
      final value = node[IndexedValueStore._values][segments.last];
      refs[value] ??= 0;
      refs[value]++;
    }
  }

  @override
  bool _delete(Map node, List<String> segments, int index) {
    if (index == segments.length - 1) {
      final segment = segments.last;

      if (!node.containsKey(_refs)) {
        return super._delete(node, segments, index);
      }

      final value = node[IndexedValueStore._values][segment];
      if (node[_refs][value] > 1) {
        node[_refs][value]--;
      } else {
        node[_refs].remove(value);
      }

      if (node[_refs].isEmpty) {
        node.remove(_refs);
      }
    }

    return super._delete(node, segments, index);
  }

  Map<T, int> _extractRefs(
    Map node, [
    Map<T, int> index = const {},
  ]) {
    if (node.containsKey(_refs)) {
      final Map<T, int> refs = node[_refs];
      for (final entry in refs.entries) {
        final key = entry.key;
        index[key] ??= 0;
        index[key] = index[key]! + entry.value;
      }
    }

    for (final key in node.keys) {
      if (key != _refs && key != IndexedValueStore._values) {
        _extractRefs(node[key], index);
      }
    }

    return index;
  }

  /// Extracts a map of the values with their ref count that exist under a given path.
  Map<T, int> extractRefs([String? path]) {
    final segments = path?.split(IndexedValueStore._delimiter) ?? [];
    final node = segments.isEmpty ? _store : _getNode(_store, segments, 0);

    if (node == null) {
      return {};
    }

    final Map<T, int> index = {};

    // If the path provided has its own value, then the ref count must include
    // a count for the initial node's value.
    if (segments.isNotEmpty && node.containsKey(IndexedValueStore._values)) {
      final segment = segments.last;
      if (node[IndexedValueStore._values].containsKey(segment)) {
        final value = node[IndexedValueStore._values][segment];
        index[value] = 1;
      }
    }

    for (final key in node.keys) {
      if (key != _refs && key != IndexedValueStore._values) {
        _extractRefs(node[key], index);
      }
    }

    return index;
  }
}
