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

  T? _get(Map node, List<String> segments, int index) {
    if (segments.isEmpty) {
      return null;
    }

    if (index < segments.length - 1) {
      final Map? child = node[segments[index]];
      if (child == null) {
        return null;
      }

      return _get(child, segments, index + 1);
    }

    return node[_values]?[segments.last];
  }

  /// Returns the value for the given path.
  T? get(String path) {
    return _get(_store, path.split(_delimiter), 0);
  }

  Map<String, T>? _getAll(Map node, List<String> segments, int index) {
    if (segments.isEmpty) {
      return null;
    }

    if (index < segments.length) {
      final child = node[segments[index]];
      if (child == null) {
        return null;
      }

      return _getAll(child, segments, index + 1);
    }

    return node[_values];
  }

  /// Returns a map of all values that are immediate children of the given path.
  Map<String, T>? getAll(String path) {
    return _getAll(_store, path.split(_delimiter), 0);
  }

  void _write(Map node, List<String> segments, int index, T value) {
    if (index < segments.length - 1) {
      final child = node[segments[index]] ??= {};
      return _write(child, segments, index + 1, value);
    }

    final values = node[_values] ??= <String, T>{};
    values[segments.last] = value;
  }

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
}
