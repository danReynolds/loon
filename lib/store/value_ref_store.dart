part of loon;

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

    final refs = node[_refs] ??= <T, int>{};
    refs[value] ??= 0;
    refs[value]++;

    if (prevValue != null) {
      if (refs[prevValue] == 1) {
        if (refs.length == 1) {
          node.remove(_refs);
        } else {
          refs.remove(prevValue);
        }
      } else {
        refs[prevValue]--;
      }
    }

    return prevValue;
  }

  Map<T, int>? _delete(
    Map node,
    List<String> segments,
    int index,
    bool recursive,
  ) {
    final segment = segments[index];
    final Map? child = node[segment];
    Map<T, int>? refs;

    if (index < segments.length - 1) {
      if (child == null) {
        return null;
      }

      refs = _delete(child, segments, index + 1, recursive);

      if (child.isEmpty) {
        node.remove(segment);
      }
    } else {
      final Map? values = node[_BaseValueStore._values];
      refs = child?[_refs];

      if (values != null) {
        final value = values[segment];
        refs ??= {};
        refs[value] ??= 0;
        refs[value] = refs[value]! + 1;

        if (values.length == 1) {
          node.remove(_BaseValueStore._values);
        } else {
          values.remove(segment);
        }
      }

      if (recursive) {
        node.remove(segment);
      }
    }

    if (refs != null) {
      for (final entry in refs.entries) {
        final key = entry.key;
        final Map nodeRefs = node[_refs];
        final nodeRefCount = node[_refs][key];
        final childRefCount = entry.value;

        if (nodeRefCount - childRefCount == 0) {
          nodeRefs.remove(key);
        } else {
          nodeRefs[key] = nodeRefCount - childRefCount;
        }

        if (nodeRefs.isEmpty) {
          node.remove(_refs);
        }
      }
    }

    return refs;
  }

  Map<T, int>? getRefs([String path = '']) {
    if (_store.isEmpty) {
      return null;
    }

    final segments = path.split(_BaseValueStore.delimiter);
    return _getNode(
      _store,
      segments.isEmpty ? segments : segments.sublist(0, segments.length - 1),
      0,
    )?[_refs];
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
