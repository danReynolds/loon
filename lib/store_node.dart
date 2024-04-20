part of loon;

class StoreNode<T> {
  Map<String, T>? values;
  Map<String, StoreNode<T>>? children;

  StoreNode();

  List<String> _segments(String path) {
    return path.split(pathDelimiter);
  }

  T? _get(List<String> segments, int index) {
    if (segments.isEmpty) {
      return null;
    }

    if (index < segments.length - 1) {
      return children?[segments[index]]?._get(segments, index + 1);
    }

    return values?[segments.last];
  }

  /// Returns the value for the given path.
  T? get(String path) {
    final children = this.children;
    if (children == null || children.isEmpty) {
      return null;
    }

    return _get(path.split(pathDelimiter), 0);
  }

  Map<String, T>? _getAll(List<String> segments, int index) {
    if (segments.isEmpty) {
      return null;
    }

    if (index < segments.length) {
      return children?[segments[index]]?._getAll(segments, index + 1);
    }

    return values;
  }

  /// Returns a map of all values under the given path.
  Map<String, T>? getAll(String path) {
    return _getAll(path.split(pathDelimiter), 0);
  }

  void _write(List<String> segments, int index, T value) {
    if (segments.length < 2) {
      return;
    }

    if (index < segments.length - 1) {
      final children = this.children ??= {};
      final child = children[segments[index]] ??= StoreNode();
      return child._write(segments, index + 1, value);
    }

    final values = this.values ??= {};
    values[segments.last] = value;
  }

  T write(String path, T value) {
    _write(path.split(pathDelimiter), 0, value);
    return value;
  }

  void _replace(List<String> segments, int index, Map<String, T> values) {
    if (segments.length < 2) {
      return;
    }

    if (index < segments.length - 1) {
      final children = this.children ??= {};
      final child = children[segments[index]] ??= StoreNode();
      return child._replace(segments, index + 1, values);
    }

    this.values = values;
  }

  Map<String, T> replace(String path, Map<String, T> values) {
    _replace(_segments(path), 0, values);
    return values;
  }

  void _delete(List<String> segments, int index) {
    if (index < segments.length - 2) {
      final children = this.children;

      if (children == null) {
        return;
      }

      children[segments[index]]?._delete(segments, index + 1);

      if (children.isEmpty) {
        this.children = null;
      }
    }

    // If the path is to a terminal value, then it would exist on its parent's
    // value index, otherwise if the path is to an intermediary node, it would exist
    // on its parent's children index. Attempt to delete the path from both.
    final fragment = segments.last;
    children?.remove(fragment);
    values?.remove(fragment);
  }

  void delete(String path) {
    if (path.isEmpty) {
      return;
    }

    _delete(path.split(pathDelimiter), 0);
  }

  bool _contains(List<String> segments, int index) {
    if (segments.isEmpty) {
      return true;
    }

    if (index < segments.length - 1) {
      return children?[segments[index]]?._contains(segments, index + 1) ??
          false;
    }

    final fragment = segments.last;

    // If the path is to a terminal value, then it would exist on its parent's
    // value index, otherwise if the path is to an intermediary node, it would exist
    // on its parent's children index. Attempt to find the path on both.
    return children?.containsKey(fragment) ??
        values?.containsKey(fragment) ??
        false;
  }

  /// Returns whether the store contains the given path.
  bool contains(String path) {
    return _contains(path.split(pathDelimiter), 0);
  }

  void clear() {
    values?.clear();
    children?.clear();
  }

  Map inspect() {
    final Map<dynamic, dynamic> index = {
      "values": values,
      "children":
          children?.entries.fold<Map<String, dynamic>>({}, (acc, entry) {
        acc[entry.key] = entry.value.inspect();
        return acc;
      }),
    };

    return index;
  }
}
