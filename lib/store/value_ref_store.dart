part of '../loon.dart';

class ValueRefStore<T> extends _BaseValueStore<T> {
  static const _refs = '__refs';

  ValueRefStore([Map? store]) : super(store);

  T? _write(Map node, List<String> segments, int index, T value) {
    final segment = segments[index];

    T? prevValue;
    if (index == segments.length - 1) {
      final values = node[_BaseValueStore._values] ??= <String, T>{};
      prevValue = values[segment];
      values[segment] = value;
    } else {
      final Map child = node[segment] ??= {};
      prevValue = _write(child, segments, index + 1, value);
    }

    if (prevValue == value) {
      return value;
    }

    final refs = node[_refs] ??= {};
    refs[value] ??= 0;
    refs[value] = refs[value]! + 1;

    if (prevValue != null) {
      if (refs[prevValue] == 1) {
        if (refs.length == 1) {
          node.remove(_refs);
        } else {
          refs.remove(prevValue);
        }
      } else {
        refs[prevValue] = refs[prevValue]! - 1;
      }
    }

    return prevValue;
  }

  Map? _delete(
    Map node,
    List<String> segments,
    int index,
    bool recursive,
  ) {
    final segment = segments[index];
    final Map? child = node[segment];

    T? childValue;
    Map? removedRefs;

    if (index < segments.length - 1) {
      if (child == null) {
        return null;
      }

      removedRefs = _delete(child, segments, index + 1, recursive);
      if (child.isEmpty) {
        node.remove(segment);
      }
    } else {
      final Map? values = node[_BaseValueStore._values];
      if (values != null) {
        childValue = values[segment];
        if (childValue != null) {
          if (values.length == 1) {
            node.remove(_BaseValueStore._values);
          } else {
            values.remove(segment);
          }
        }
      }

      if (recursive && child != null) {
        removedRefs = child[_refs]!;

        if (childValue != null) {
          removedRefs![childValue] ??= 0;
          removedRefs[childValue] = removedRefs[childValue]! + 1;
        }

        node.remove(segment);
      } else if (childValue != null) {
        removedRefs = {childValue: 1};
      }
    }

    if (removedRefs != null) {
      final Map nodeRefs = node[_refs];

      for (final entry in removedRefs.entries) {
        final key = entry.key;
        final nodeRefCount = node[_refs][key];
        final childRefCount = entry.value;

        if (nodeRefCount == childRefCount) {
          nodeRefs.remove(key);
        } else {
          nodeRefs[key] = nodeRefCount - childRefCount;
        }

        if (nodeRefs.isEmpty) {
          node.remove(_refs);
        }
      }
    }

    return removedRefs;
  }

  /// Returns a map of all values that exist under the given path to their ref count.
  Map<T, int>? getRefs([String path = '']) {
    if (_store.isEmpty) {
      return null;
    }

    Map? node = _store;

    if (path.isNotEmpty) {
      final segments = _getSegments(path);
      node = _getNode(
        _store,
        segments.isEmpty ? segments : segments.sublist(0, segments.length),
      );

      if (node == null) {
        return null;
      }
    }

    final refs = node[_refs];
    if (refs is Map<T, int>?) {
      return refs;
    }

    // If the store was hydrated, then the refs may have been instantiated as a
    // `Map<String, dynamic>` in which case it must be converted to a Map<String, int>.
    return node[_refs] = Map<T, int>.from(refs);
  }

  @override

  /// A [ValueRefStore] overrides the default [ValueStore.extractValues] behavior
  /// since the values under a given path are pre-computed by the ref store.
  Set<T> extractValues([String path = '']) {
    return getRefs(path)?.keys.toSet() ?? {};
  }

  @override
  T write(String path, T value) {
    _write(_store, path.split(_BaseValueStore.delimiter), 0, value);
    return value;
  }

  @override
  delete(
    String path, {
    bool recursive = true,
  }) {
    if (path.isEmpty) {
      _store = {};
      return;
    }

    _delete(_store, path.split(_BaseValueStore.delimiter), 0, recursive);
  }
}
