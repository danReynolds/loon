part of loon;

abstract class _BaseValueStore<T> {
  Map _store = {};

  static const _values = '__values';
  static const delimiter = '__';
  static const root = '';

  _BaseValueStore([Map? store]) {
    if (store != null) {
      _store = store;
    }
  }

  List<String> _getSegments(String path) {
    return path.split(delimiter);
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

    final rootValue = _store[_values]?[root];
    if (index == 0 && rootValue != null) {
      return (root, rootValue);
    }

    return null;
  }

  Map<String, T> _extractParentPath(
    Map node,
    List<String> segments,
    int index,
    Map<String, T> values,
  ) {
    final segment = segments[index];

    final child = node[segment];
    final value = node[_values]?[segment];

    if (value != null) {
      final path = segments.sublist(0, index + 1).join(delimiter);
      values[path] = value;
    }
    if (index < segments.length - 1 && child != null) {
      _extractParentPath(child, segments, index + 1, values);
    }

    final rootValue = _store[_values]?[root];
    if (index == 0 && rootValue != null) {
      values[ValueStore.root] = rootValue;
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

  Map<String, T> _extract(
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
        _extract(node[key], values, childPath);
      }
    }

    return values;
  }

  Set<T> _extractValues(Map? node, Set<T> values) {
    if (node == null) {
      return values;
    }

    final Map<String, T>? nodeValues = node[_values];

    if (nodeValues != null) {
      values.addAll(nodeValues.values);
    }

    for (final key in node.keys) {
      if (key != _values) {
        _extractValues(node[key], values);
      }
    }

    return values;
  }

  T? get(String path) {
    if (_store.isEmpty) {
      return null;
    }

    final segments = _getSegments(path);
    return _getNode(
      _store,
      segments.sublist(0, segments.length - 1),
      0,
    )?[_values]?[segments.last];
  }

  /// Returns a map of all values that are immediate children of the given path.
  Map<String, T>? getChildValues(String path) {
    return _getNode(_store, _getSegments(path), 0)?[_values];
  }

  /// Returns the nearest path/value pair that has a value along the given path, beginning at the full path
  /// and then attempting to find a non-null value at any parent node moving up the tree.
  (String, T)? getNearest(String path) {
    return _getNearest(_store, _getSegments(path), 0, null);
  }

  /// Returns the nearest path that has a matching value along the given path.
  String? getNearestMatch(String path, T value) {
    return _getNearest(_store, _getSegments(path), 0, value)?.$1;
  }

  bool hasValue(String path) {
    return get(path) != null;
  }

  bool hasPath(String path) {
    if (path.isEmpty) {
      return true;
    }

    return hasValue(path) || _getNode(_store, _getSegments(path), 0) != null;
  }

  T write(String path, T value);
  void delete(String path, {bool recursive = true});

  /// Extracts all values under the given path into a set of flat key-value pairs of paths to values.
  Map<String, T> extract([String path = '']) {
    if (path.isEmpty) {
      return _extract(_store, {}, path);
    }

    final Map<String, T> values = {};
    final segments = _getSegments(path);
    final lastSegment = segments.removeLast();

    final parentNode = _getNode(_store, segments, 0);

    if (parentNode == null) {
      return values;
    }

    if (parentNode[_values]?.containsKey(lastSegment) ?? false) {
      values[path] = parentNode[_values][lastSegment];
    }

    return _extract(parentNode[lastSegment], values, path);
  }

  /// Extracts all values at parent paths of the given path into a set of flat key-value pairs of paths to values.
  /// For example, if the path is users__1__friends__1 and both users__1 and users__1__friends__1
  /// exist as distinct values in the store, then it returns both values.
  Map<String, T> extractParentPath(String path) {
    return _extractParentPath(_store, _getSegments(path), 0, {});
  }

  /// Returns a set of the unique values that exist in the store under the given path.
  Set<T> extractValues([String path = '']) {
    if (path.isEmpty) {
      return _extractValues(_store, {});
    }

    final Set<T> values = {};
    final segments = _getSegments(path);
    final lastSegment = segments.removeLast();

    final parentNode = _getNode(_store, segments, 0);
    if (parentNode == null) {
      return values;
    }

    if (parentNode[_values]?.containsKey(lastSegment) ?? false) {
      values.add(parentNode[_values][lastSegment]);
    }

    return _extractValues(parentNode[lastSegment], values);
  }

  Map touch(String path) {
    return _touch(_store, path.split(delimiter), 0);
  }

  bool get isEmpty {
    return _store.isEmpty;
  }

  /// Returns whether the store has any child values under the given path.
  bool hasChildValues(String path) {
    return getChildValues(path)?.isNotEmpty ?? false;
  }

  void clear() {
    _store = {};
  }

  Map inspect() {
    return _store;
  }
}
