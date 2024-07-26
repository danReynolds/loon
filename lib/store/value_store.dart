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

  ValueStore({
    Map? store,
  }) {
    if (store != null) {
      _store = store;
    }
  }

  static ValueStore<Json> fromJson(Json json) {
    return ValueStore<Json>(store: json);
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

    return node[_values]?[segments[index]];
  }

  /// Returns the nearest value along the given path, beginning at the full path
  /// and then attempting to find a non-null value for any parent node moving up the tree.
  T? getNearest(String path) {
    return _getNearest(_store, path.split(delimiter), 0);
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

  String? _findValue(
    Map? node,
    List<String> segments,
    int index,
    dynamic value,
  ) {
    if (node == null) {
      return null;
    }

    final segment = segments[index];
    if (node[_values]?[segment] == value) {
      return segments.take(index + 1).join(delimiter);
    }

    if (index < segments.length - 1) {
      return _findValue(node[segment], segments, index + 1, value);
    }

    return null;
  }

  /// Returns the first subpath along the given path that has a value equal to the
  /// provided value (if any).
  String? findValue(String path, dynamic value) {
    return _findValue(_store, path.split(delimiter), 0, value);
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
    String path = '',
  ]) {
    if (path.isEmpty) {
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

  /// Extracts all values under the given path in the store into a set of flat key-value pairs of paths to values.
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

/// An extension of the [ValueStore] that additionally keeps a ref count of each distinct
/// value indexed under a path.
///
/// Ex.
/// ```dart
/// final store = RefValueStore<String>();
/// store.write('users__2__messages__1', 'Test');
/// store.write('users__2__messages__2', 'Test again');
/// store.write('users__2__messages__3', 'Test again');
///
/// print(store.inspect());
/// {
///   users: {
///     2: {
///       messages: {
///         "__refs": {
///            "Test": 1,
///            "Test again": 2,
///          },
///         __values: {
///           1: "Test",
///           2: "Test again",
///           3: "Test again",
///         }
///       }
///     }
///   }
/// }
/// ```
class RefValueStore<T> extends ValueStore<T> {
  static const _refs = '__refs';

  RefValueStore([Map? store]) {
    if (store != null) {
      _store = store;
    }
  }

  @override
  Map _mergeNode(Map node, Map otherNode) {
    final result = super._mergeNode(node, otherNode);

    final otherValues = otherNode[ValueStore._values];
    if (otherValues != null) {
      node[_refs] ??= <T, int>{};

      for (final value in otherValues) {
        node[_refs][value] ??= 0;
        node[_refs][value]++;
      }
    }

    return result;
  }

  @override
  bool _graft(node, otherNode, segments, index) {
    if (index == segments.length - 1) {
      final segment = segments[index];
      final otherValues = otherNode?[ValueStore._values];

      // An [RefValueStore] must additionally update the ref count on the
      // source and destination store's parent node's value.
      if (otherValues != null && otherValues.containsKey(segment)) {
        final otherValue = otherValues[segment];
        final Map otherRefs = otherNode![_refs];

        if (otherRefs[otherValue] == 1) {
          otherRefs.remove(otherValue);
        } else {
          otherRefs[otherValue]--;
        }

        if (otherRefs.isEmpty) {
          otherNode.remove(_refs);
        }

        if (node[ValueStore._values].containsKey(segment)) {
          final value = node[ValueStore._values][segment];
          if (node[_refs][value] == 1) {
            node[_refs].remove(value);
          } else {
            node[_refs][value]--;
          }

          if (value != otherValue) {
            node[_refs][otherValue] ??= 0;
            node[_refs][otherValue]++;
          }
        } else {
          node[_refs][otherValue] ??= 0;
          node[_refs][otherValue]++;
        }
      }
    }

    return super._graft(node, otherNode, segments, index);
  }

  @override
  graft(
    other, [
    path = '',
  ]) {
    if (path.isEmpty) {
      return super.graft(other, path);
    }

    _graft(_store, other._store, path.split(ValueStore.delimiter), 0);
  }

  @override
  void _write(Map node, List<String> segments, int index, T value) {
    if (index == segments.length - 1) {
      final segment = segments[index];
      final values = node[ValueStore._values];
      final refs = node[_refs] ??= <T, int>{};

      // Check if there was a previous value for this path.
      if (values != null && values.containsKey(segment)) {
        final prevValue = values[segment];

        // If the value has not changed, then do not modify the ref count.
        if (prevValue == value) {
          return;
        }

        // Otherwise decrement the ref count of the old value.
        if (refs[prevValue] == 1) {
          refs.remove(prevValue);
        } else {
          refs[prevValue]--;
        }
      }

      // Increment the ref count of the new value.
      refs[value] ??= 0;
      refs[value]++;
    }

    super._write(node, segments, index, value);
  }

  @override
  bool _delete(
    Map node,
    List<String> segments,
    int index, [
    bool recursive = true,
  ]) {
    if (index == segments.length - 1) {
      final segment = segments.last;

      if (!node.containsKey(_refs)) {
        return super._delete(node, segments, index, recursive);
      }

      if (node[ValueStore._values].containsKey(segment)) {
        final value = node[ValueStore._values][segment];

        if (node[_refs][value] > 1) {
          node[_refs][value]--;
        } else {
          node[_refs].remove(value);
        }

        if (node[_refs].isEmpty) {
          node.remove(_refs);
        }
      }
    }

    return super._delete(node, segments, index, recursive);
  }

  Map<T, int> _extractRefs(
    Map node, [
    Map<T, int> index = const {},
  ]) {
    if (node.containsKey(_refs)) {
      final Map refs = node[_refs];
      for (final entry in refs.entries) {
        final key = entry.key;
        index[key] ??= 0;
        index[key] = index[key]! + entry.value as int;
      }
    }

    for (final key in node.keys) {
      if (key != _refs && key != ValueStore._values) {
        _extractRefs(node[key], index);
      }
    }

    return index;
  }

  /// Extracts a map of the values with their ref count that exist under a given path.
  Map<T, int> extractRefs([String path = '']) {
    final Map<T, int> index = {};

    if (path.isEmpty) {
      for (final key in _store.keys) {
        if (key != _refs && key != ValueStore._values) {
          _extractRefs(_store[key], index);
        }
      }
      return index;
    }

    final segments = path.split(ValueStore.delimiter);
    final parent =
        _getNode(_store, segments.sublist(0, segments.length - 1), 0);
    if (parent == null) {
      return index;
    }

    // If the parent node has the final path segment as a value, then the ref count must include
    // a count for the final node's value.
    if (parent.containsKey(ValueStore._values)) {
      final segment = segments.last;
      if (parent[ValueStore._values].containsKey(segment)) {
        final value = parent[ValueStore._values][segment];
        index[value] = 1;
      }
    }

    final child = parent[segments.last];
    if (child == null) {
      return index;
    }

    _extractRefs(child, index);

    return index;
  }
}
