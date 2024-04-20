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

  /// Returns a map of all values under the given path.
  Map<String, T>? getAll(String path) {
    return _getAll(_store, path.split(_delimiter), 0);
  }

  void _write(Map node, List<String> segments, int index, T value) {
    if (segments.length < 2) {
      return;
    }

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

  // users__1__messages__2
  // Deletes the path from the store. Returns whether the node is empty after the removal.
  bool _delete(Map node, List<String> segments, int index) {
    if (index < segments.length - 1) {
      final segment = segments[index];
      final Map? child = node[segment];

      if (child == null) {
        return false;
      }

      if (_delete(child, segments, index + 1) && node.length == 1) {
        return true;
      }

      node.remove(segment);
      return false;
    }

    final segment = segments.last;
    if (node.length == 1) {
      if (node.containsKey(segment)) {
        return true;
      }

      final Map values = node[_values];
      if (values.length == 1) {
        return true;
      }

      values.remove(segment);
      return false;
    }

    if (node.containsKey(segment)) {
      node.remove(segment);
      return false;
    }

    node[_values].remove(segment);
    return false;
  }

  void delete(String path) {
    if (path.isEmpty) {
      return;
    }
    _delete(_store, path.split(_delimiter), 0);
  }

  bool _contains(Map node, List<String> segments, int index) {
    if (segments.isEmpty) {
      return true;
    }

    if (index < segments.length - 1) {
      final child = node[segments[index]];

      if (child == null) {
        return false;
      }

      return _contains(child, segments, index + 1);
    }

    final segment = segments.last;

    // If the path is to a terminal value, then it would exist on its parent's
    // value index, otherwise if the path is to an intermediary node, it would exist
    // on its parent's children index. Attempt to find the path on both.

    return node.containsKey(segment) ||
        (node[_values]?.containsKey(segment) ?? false);
  }

  /// Returns whether the store contains the given path.
  bool contains(String path) {
    return _contains(_store, path.split(_delimiter), 0);
  }

  void clear() {
    _store.clear();
  }

  Map inspect() {
    return _store;
  }
}
