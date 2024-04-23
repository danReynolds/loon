part of loon;

class ValueStore<T> {
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
    final Map? values = node[_values];

    node.remove(segment);
    values?.remove(segment);

    // The final segment of the path is removed from the child value tree as well as
    // from the values of the parent node.
    return node.isEmpty || node.length == 1 && (values?.isEmpty ?? false);
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
