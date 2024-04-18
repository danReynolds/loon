part of loon;

const pathDelimiter = '__';

class StoreNode<T> {
  Map<String, T>? values;
  Map<String, StoreNode<T>>? children;

  StoreNode();

  T? _get(List<String> fragments, int index) {
    if (fragments.isEmpty) {
      return null;
    }

    if (index < fragments.length - 1) {
      return children?[fragments[index]]?._get(fragments, index + 1);
    }

    return values?[fragments.last];
  }

  /// Returns the value for the given path.
  T? get(String path) {
    final children = this.children;
    if (children == null || children.isEmpty) {
      return null;
    }

    return _get(path.split(pathDelimiter), 0);
  }

  Map<String, T>? _getAll(List<String> fragments, int index) {
    if (fragments.isEmpty) {
      return null;
    }

    if (index < fragments.length) {
      return children?[fragments[index]]?._getAll(fragments, index + 1);
    }

    return values;
  }

  /// Returns a map of all values under the given path.
  Map<String, T>? getAll(String path) {
    return _getAll(path.split(pathDelimiter), 0);
  }

  void _write(List<String> fragments, int index, T value) {
    if (fragments.length < 2) {
      return;
    }

    if (index < fragments.length - 1) {
      final children = this.children ??= {};
      final child = children[fragments[index]] ??= StoreNode();
      child._write(fragments, index + 1, value);
      return;
    }

    final values = this.values ??= {};
    values[fragments.last] = value;
  }

  void write(String path, T value) {
    _write(path.split(pathDelimiter), 0, value);
  }

  void _delete(List<String> fragments, int index) {
    if (index < fragments.length - 2) {
      return children?[fragments[index]]?._delete(fragments, index + 1);
    }

    // If the path is to a terminal value, then it would exist on its parent's
    // value index, otherwise if the path is to an intermediary node, it would exist
    // on its parent's children index. Attempt to delete the path from both.
    final fragment = fragments.last;
    children?.remove(fragment);
    values?.remove(fragment);
  }

  void delete(String path) {
    if (path.isEmpty) {
      return;
    }

    _delete(path.split(pathDelimiter), 0);
  }

  bool _contains(List<String> fragments, int index) {
    if (fragments.isEmpty) {
      return true;
    }

    if (index < fragments.length - 1) {
      return children?[fragments[index]]?._contains(fragments, index + 1) ??
          false;
    }

    final fragment = fragments.last;

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
