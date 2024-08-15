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
class ValueStore<T> extends _BaseValueStore<T> {
  ValueStore([Map? store]) : super(store);

  static const root = _BaseValueStore.root;

  static ValueStore fromJson(Json json) {
    return ValueStore(json);
  }

  /// Merges the values and child keys of the given other node into the given node.
  Map _mergeNode(Map node, Map otherNode) {
    for (final entry in otherNode.entries) {
      final key = entry.key;

      if (key == _BaseValueStore._values) {
        if (node.containsKey(_BaseValueStore._values)) {
          node[_BaseValueStore._values] = {
            ...(node[_BaseValueStore._values] as Map),
            ...entry.value,
          };
        } else {
          node[_BaseValueStore._values] = entry.value;
        }
      } else if (node.containsKey(key)) {
        node[key] = _mergeNode(node[key], otherNode[key]);
      } else {
        node[key] = entry.value;
      }
    }

    return node;
  }

  void _write(Map node, List<String> segments, int index, T value) {
    if (index < segments.length - 1) {
      final child = node[segments[index]] ??= {};
      return _write(child, segments, index + 1, value);
    }

    final values = node[_BaseValueStore._values] ??= <String, T>{};
    values[segments.last] = value;
  }

  @override
  write(String path, T value) {
    _write(_store, path.split(_BaseValueStore.delimiter), 0, value);
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
        if (child.keys.length == 1 &&
            child.containsKey(_BaseValueStore._values)) {
          node.remove(segment);
        } else {
          child.remove(_BaseValueStore._values);
        }
      }
    }

    if (node.containsKey(_BaseValueStore._values)) {
      final Map values = node[_BaseValueStore._values];
      values.remove(segment);

      if (values.isEmpty) {
        node.remove(_BaseValueStore._values);
      }
    }

    return node.isEmpty;
  }

  /// Deletes the values at the given path and optionally its subtree from the store.
  @override
  delete(
    String path, {
    /// Whether the data in the subtree under the given path should also be deleted.
    /// If false, only the values at the given path are deleted and the subtree is maintained.
    bool recursive = true,
  }) {
    if (path.isEmpty) {
      _store = {};
      return;
    }

    _delete(_store, path.split(_BaseValueStore.delimiter), 0, recursive);
  }

  /// Returns whether the store has a value for the given path.
  @override
  bool hasValue(String path) {
    return get(path) != null;
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

    if (otherNode.containsKey(_BaseValueStore._values)) {
      final otherValues = otherNode[_BaseValueStore._values];

      if (otherValues.containsKey(segment)) {
        final value = otherValues.remove(segment);

        final values = node[_BaseValueStore._values] ??= {};
        values[segment] = value;
      }

      if (otherNode[_BaseValueStore._values].isEmpty) {
        otherNode.remove(_BaseValueStore._values);
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
      _graft(_store, other._store, path.split(_BaseValueStore.delimiter), 0);
    }
  }

  Map toJson() {
    return _store;
  }
}
