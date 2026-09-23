part of '../loon.dart';

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
  ValueStore([super.store]);

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

  @override
  write(String path, T value) {
    final (parent, start) = _resolveParent(path, create: true)!;
    final values = parent[_BaseValueStore._values] ??= <String, T>{};
    values[path.substring(start)] = value;
    return value;
  }

  /// Writes [value] at [path] unless it already has a value, returning whether it was written.
  bool putIfAbsent(String path, T value) {
    final (parent, start) = _resolveParent(path, create: true)!;
    final Map<String, T> values =
        parent[_BaseValueStore._values] ??= <String, T>{};
    final key = path.substring(start);
    if (values[key] != null) {
      return false;
    }
    values[key] = value;
    return true;
  }

  /// Deletes all data under the segment of the path beginning at [start]. Returns whether
  /// the current node can be deleted as well as a result of the deleted path.
  bool _delete(
    Map node,
    String path,
    int start, [
    bool recursive = true,
  ]) {
    final end = _nextStoreDelimiter(path, start);

    if (end >= 0) {
      final segment = path.substring(start, end);
      final Map? child = node[segment];

      if (child == null) {
        return false;
      }

      if (_delete(
          child, path, end + _BaseValueStore.delimiter.length, recursive)) {
        if (node.length == 1) {
          if (start == 0) {
            node.remove(segment);
          }

          return true;
        }

        node.remove(segment);
      }
      return false;
    }

    final segment = path.substring(start);
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
    _forgetLastParent();

    if (path.isEmpty) {
      _store = {};
      return;
    }

    if (_store.isEmpty) return;

    _delete(_store, path, 0, recursive);
  }

  /// Grafts the data under the given path from the other store into this store. Returns
  /// whether the other store's node can be deleted after grafted.
  bool _graft(Map node, Map? otherNode, String path, int start) {
    if (otherNode == null) {
      return false;
    }

    final end = _nextStoreDelimiter(path, start);
    final segment = path.substring(start, end < 0 ? path.length : end);

    if (end >= 0) {
      final Map? otherChildNode = otherNode[segment];

      if (otherChildNode == null) {
        return false;
      }

      final Map childNode = node[segment] ??= {};

      if (_graft(childNode, otherChildNode, path,
          end + _BaseValueStore.delimiter.length)) {
        if (otherNode.length == 1) {
          if (start == 0) {
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
      other._forgetLastParent();
      _graft(_store, other._store, path, 0);
    }
  }
}
