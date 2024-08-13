part of loon;

abstract class _BaseValueStore<T> {
  Map _store = {};

  static const _values = '__values';
  static const delimiter = '__';

  _BaseValueStore([Map? store]) {
    if (store != null) {
      _store = store;
    }
  }

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

  List<T> _getSubpathValues(
    Map node,
    List<String> segments,
    int index,
  ) {
    final segment = segments[index];

    final child = node[segment];
    final value = node[_values]?[segment];

    final List<T> values = [];

    if (value != null) {
      values.add(value);
    }
    if (index < segments.length - 1 && child != null) {
      values.addAll(_getSubpathValues(child, segments, index + 1));
    }

    return values;
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

  /// Returns a map of all values that are immediate children of the given path.
  Map<String, T>? getValues(String path) {
    return _getNode(_store, path.split(delimiter), 0)?[_values];
  }

  /// Returns all values along the given path at every sub path.
  /// For example, if the path is users__1__friends__1 and both users__1 and users__1__friends__1
  /// exist as distinct values in the store, then it returns both values.
  List<T> getSubpathValues(String path) {
    return _getSubpathValues(_store, path.split(delimiter), 0);
  }

  /// Returns the nearest path/value pair that has a matching value along the given path, beginning at the full path
  /// and then attempting to find the value at any parent node moving up the tree. If no value is provided, it returns
  /// the nearest non-null path.
  (String, T)? getNearest(String path, [T? value]) {
    return _getNearest(_store, path.split(delimiter), 0, value);
  }

  bool hasValue(String path) {
    return get(path) != null;
  }

  bool hasPath(String path) {
    if (path.isEmpty) {
      return true;
    }

    return hasValue(path) || _getNode(_store, path.split(delimiter), 0) != null;
  }

  T write(String path, T value);
  void delete(String path, {bool recursive = true});

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

  Map touch(String path) {
    return _touch(_store, path.split(delimiter), 0);
  }

  bool get isEmpty {
    return _store.isEmpty;
  }

  /// Returns whether the store has any child values under the given path.
  bool hasValues(String path) {
    return getValues(path)?.isNotEmpty ?? false;
  }

  void clear() {
    _store = {};
  }

  Map inspect() {
    return _store;
  }
}
