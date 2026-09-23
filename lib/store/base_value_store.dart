part of '../loon.dart';

abstract class _BaseValueStore<T> {
  Map _store = {};

  /// The last resolved path, the index at which its final segment begins, and the node that owns
  /// that segment. Paths under one parent are often resolved in a row, such as the documents of a
  /// collection, so they reuse the parent node rather than walking to it again. Any operation that
  /// removes nodes forgets it.
  String? _lastPath;
  int _lastSegmentStart = 0;
  Map? _lastParent;

  static const _values = '__values';
  static const delimiter = '__';
  static const root = '';

  _BaseValueStore([Map? store]) {
    if (store != null) {
      _store = store;
    }
  }

  void _forgetLastParent() {
    _lastPath = null;
    _lastParent = null;
  }

  /// Whether [path] has the same parent as the last resolved path. Their segments before the final
  /// one are identical, so they split the same way up to it.
  @pragma('vm:prefer-inline')
  bool _hasLastParent(String path) {
    final lastPath = _lastPath;
    if (lastPath == null) {
      return false;
    }
    if (identical(path, lastPath)) {
      return true;
    }

    final start = _lastSegmentStart;
    if (path.length < start) {
      return false;
    }
    for (var i = 0; i < start; i++) {
      if (path.codeUnitAt(i) != lastPath.codeUnitAt(i)) {
        return false;
      }
    }
    return _nextStoreDelimiter(path, start) < 0;
  }

  /// Returns the node that owns the final segment of [path] and the index at which that segment
  /// begins, or null if a node along the path is missing. If [create] is true, missing nodes are
  /// created instead.
  ///
  /// Segments are parsed as they are visited rather than split up front, so a lookup allocates
  /// only the segments it reaches and stops at the first missing node.
  @pragma('vm:prefer-inline')
  (Map, int)? _resolveParent(String path, {bool create = false}) {
    if (_hasLastParent(path)) {
      return (_lastParent!, _lastSegmentStart);
    }

    Map node = _store;
    var start = 0;
    while (true) {
      final end = _nextStoreDelimiter(path, start);
      if (end < 0) {
        break;
      }

      final segment = path.substring(start, end);
      final Map? child = create ? (node[segment] ??= {}) : node[segment];
      if (child == null) {
        return null;
      }
      node = child;
      start = end + delimiter.length;
    }

    _lastPath = path;
    _lastSegmentStart = start;
    _lastParent = node;
    return (node, start);
  }

  /// Returns the node that owns the final segment of [path] together with that segment, or null
  /// if the parent node is missing. `parent[_values][segment]` is the path's value and
  /// `parent[segment]` its child node.
  @pragma('vm:prefer-inline')
  (Map, String)? _getParent(String path) {
    if (_store.isEmpty) {
      return null;
    }

    if (_resolveParent(path) case (final parent, final start)) {
      return (parent, path.substring(start));
    }
    return null;
  }

  Map? _getNode(String path) {
    if (_getParent(path) case (final parent, final segment)) {
      return parent[segment];
    }
    return null;
  }

  (String, T)? _getNearest(
    Map? node,
    String path,
    int start,
    T? value,
  ) {
    if (node == null) {
      return null;
    }

    final end = _nextStoreDelimiter(path, start);
    final segment = path.substring(start, end < 0 ? path.length : end);

    if (end >= 0) {
      final result =
          _getNearest(node[segment], path, end + delimiter.length, value);
      if (result != null) {
        return result;
      }
    }

    final nodeValue = node[_values]?[segment];
    if (nodeValue != null && (value == null || nodeValue == value)) {
      return (end < 0 ? path : path.substring(0, end), nodeValue);
    }

    if (start > 0) {
      return null;
    }

    if (_store[_values]?[root] case T rootValue) {
      return (root, rootValue);
    }

    return null;
  }

  Map<String, T> _extractParentPath(
    Map node,
    String path,
    int start,
    Map<String, T> values,
  ) {
    while (true) {
      final end = _nextStoreDelimiter(path, start);
      final segment = path.substring(start, end < 0 ? path.length : end);
      final value = node[_values]?[segment];
      if (value != null) {
        values[end < 0 ? path : path.substring(0, end)] = value;
      }
      if (end < 0) break;
      final Map? child = node[segment];
      if (child == null) break;
      node = child;
      start = end + delimiter.length;
    }
    final rootValue = _store[_values]?[root];
    if (rootValue != null) values[ValueStore.root] = rootValue;
    return values;
  }

  Map<String, T> _extract(
    Map? node,
    Map<String, T> values,
    String path,
  ) {
    if (node == null) {
      return values;
    }

    final Map? localValues = node[_values];
    if (localValues != null) {
      localValues.forEach((key, value) {
        values[path.isEmpty ? key : '$path$delimiter$key'] = value;
      });
      if (node.length == 1) return values;
    }

    node.forEach((key, child) {
      if (key != _values) {
        _extract(child, values, path.isEmpty ? key : '$path$delimiter$key');
      }
    });

    return values;
  }

  Set<T> _extractValues(Map? node, Set<T> values) {
    if (node == null) {
      return values;
    }

    final Map<String, T>? nodeValues = node[_values];

    if (nodeValues != null) {
      values.addAll(nodeValues.values);
      if (node.length == 1) return values;
    }

    node.forEach((key, child) {
      if (key != _values) _extractValues(child, values);
    });

    return values;
  }

  T? get(String path) {
    if (_getParent(path) case (final parent, final segment)) {
      return parent[_values]?[segment];
    }
    return null;
  }

  /// Returns a map of all values that are immediate children of the given path.
  Map<String, T>? getChildValues(String path) {
    return _getNode(path)?[_values];
  }

  /// Returns the nearest path/value pair that has a value along the given path, beginning at the full path
  /// and then attempting to find a non-null value at any parent node moving up the tree.
  (String, T)? getNearest(String path) {
    return _getNearest(_store, path, 0, null);
  }

  /// Returns the nearest path that has a matching value along the given path.
  String? getNearestMatch(String path, T value) {
    return _getNearest(_store, path, 0, value)?.$1;
  }

  bool hasValue(String path) {
    return get(path) != null;
  }

  /// Returns whether the path exists in the store, either as a value or path to another descendant value.
  bool hasPath(String path) {
    if (path.isEmpty) return true;
    if (_getParent(path) case (final parent, final segment)) {
      return parent[_values]?[segment] != null || parent[segment] != null;
    }
    return false;
  }

  T write(String path, T value);
  void delete(String path, {bool recursive = true});

  /// Extracts all values under the given path into a map of flattened paths to values.
  Map<String, T> extract([String path = '']) {
    if (path.isEmpty) {
      return _extract(_store, {}, path);
    }

    final Map<String, T> values = {};

    if (_getParent(path) case (final parent, final segment)) {
      if (parent[_values]?.containsKey(segment) ?? false) {
        values[path] = parent[_values][segment];
      }

      return _extract(parent[segment], values, path);
    }

    return values;
  }

  /// Extracts all values at parent paths of the given path into a set of flat key-value pairs of paths to values.
  /// For example, if the path is users__1__friends__1 and both users__1 and users__1__friends__1
  /// exist as distinct values in the store, then it returns both values.
  Map<String, T> extractParentPath(String path) {
    return _extractParentPath(_store, path, 0, {});
  }

  /// Returns a set of the unique values that exist in the store under the given path.
  Set<T> extractValues([String path = '']) {
    if (path.isEmpty) {
      return _extractValues(_store, {});
    }

    final Set<T> values = {};

    if (_getParent(path) case (final parent, final segment)) {
      if (parent[_values]?.containsKey(segment) ?? false) {
        values.add(parent[_values][segment]);
      }

      return _extractValues(parent[segment], values);
    }

    return values;
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
    _forgetLastParent();
  }

  Map inspect() {
    return _store;
  }

  /// While unreferenced in the codebase, toJson is implemented so that the store can be serialized
  /// using the default behavior of [jsonEncode] which is to attempt to call [toJson] on complex objects.
  Map toJson() {
    return inspect();
  }

}
