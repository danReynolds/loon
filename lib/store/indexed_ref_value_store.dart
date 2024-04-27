part of loon;

/// An indexed ref value store is a similar tree structure to the [IndexedValueStore], with the added feature of maintaining
/// a record of the number of references to each value in the parent path's index.
///
/// Ex.
///
/// ```dart
/// final store = IndexedRefValueStore();
/// store.write('users__1__posts__1', 'Test');
/// store.write('users__1__posts__2', 'Test');
/// store.write('users__1__posts__3', 'Test 2');
///
/// {
///   users: {
///     1: {
///       posts: {
///         __refs: {
///           'Test': 2,
///           'Test 2': 1,
///         }
///         1: 'Test',
///         2: 'Test',
///         3: 'Test 2',
///       }
///     }
///   }
/// }
/// ```

class IndexedRefValueStore<T> {
  final Map _store = {};

  static const _delimiter = '__';
  static const _values = '__values';
  static const _refs = '__refs';

  int _getRef(Map? node, List<String> segments, int index, T value) {
    if (node == null || segments.isEmpty) {
      return 0;
    }

    if (index < segments.length) {
      return _getRef(node[segments[index]], segments, index + 1, value);
    }

    return node[_refs]?[value] ?? 0;
  }

  /// Returns the ref count for the value at the given path.
  int getRef(String path, T value) {
    return _getRef(_store, path.split(_delimiter), 0, value);
  }

  T? _get(Map? node, List<String> segments, int index) {
    if (node == null || segments.isEmpty) {
      return null;
    }

    if (index < segments.length - 1) {
      return _get(node[segments[index]], segments, index + 1);
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
    final refs = node[_refs] ??= <T, int>{};

    refs[value] ??= 0;
    refs[value]++;
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

      if (_delete(child, segments, index + 1)) {
        node.remove(segment);
        return node.isEmpty;
      }

      return false;
    }

    final segment = segments.last;
    node.remove(segment);

    if (node.containsKey(_values)) {
      final Map values = node[_values];

      if (values.containsKey(segment)) {
        final value = values.remove(segment);

        if (values.isEmpty) {
          node.remove(_values);
        }

        if (node.containsKey(_refs)) {
          final Map refs = node[_refs];
          if (refs.containsKey(value)) {
            refs[value]--;

            if (refs[value] == 0) {
              refs.remove(value);
            }
          }

          if (refs.isEmpty) {
            node.remove(_refs);
          }
        }
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

  Map inspect() {
    return _store;
  }
}
