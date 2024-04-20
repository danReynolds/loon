part of loon;

class DepStore {
  final _store = {};

  static const _delimiter = '__';
  static const _depKey = '__deps';

  Map? _get(Map? node, List<String> segments, int index) {
    if (node == null) {
      return null;
    }

    if (index < segments.length - 1) {
      return _get(node[segments[index]], segments, index + 1);
    }

    return node;
  }

  Map? get(String path) {
    return _get(_store, path.split(_delimiter), 0);
  }

  /// Increments the dep count at the given path from the node.
  void _inc(Map node, List<String> segments, [int index = 0]) {
    if (index < segments.length - 1) {
      final child = node[segments[index]] ??= {};
      return _inc(child, segments, index + 1);
    }

    final segment = segments.last;
    if (node.containsKey(segment)) {
      node[segment]++;
    } else {
      node[segment] = 1;
    }
  }

  /// Decrements the dep count at the given path from the node, Returns whether
  /// the node can be deleted after the decrement.
  bool _dec(Map node, List<String> segments, [int index = 0]) {
    if (index < segments.length - 1) {
      final Map? child = node[segments[index]];

      if (child == null) {
        return node.isEmpty;
      }

      if (_dec(child, segments, index + 1) && child.length == 1) {
        return true;
      }

      child.remove(segments[index + 1]);
      return false;
    }

    final segment = segments.last;
    if (node[segment] == 1) {
      return true;
    }

    node[segment]--;
    return false;
  }

  void _addDep(
    Map node,
    List<String> segments,
    List<String> depSegments, [
    int index = 0,
  ]) {
    if (index < segments.length - 2) {
      final segment = segments[index];
      final child = node[segment] ??= {};
      return _addDep(child, segments, depSegments, index + 1);
    }

    final collection = node[segments[index]] ??= {};
    final doc = collection[segments[index + 1]] ??= {};
    final collectionDeps = collection[_depKey] ??= {};
    final docDeps = doc[_depKey] ??= {};

    _inc(collectionDeps, depSegments);
    _inc(docDeps, depSegments);
  }

  void addDep(String path, String depPath) {
    final pathSegments = path.split(_delimiter);
    final depSegments = depPath.split(_delimiter);
    _addDep(_store, pathSegments, depSegments);
  }

  /// Removes the dependency from the node. Returns whether the node can be deleted.
  bool _removeDep(
    Map node,
    List<String> segments,
    List<String> depSegments, [
    int index = 0,
  ]) {
    // The recursion down the path tree stops at the collection node of the final segment, since both
    // the collection and document node need to have the dependency removed.
    if (index < segments.length - 2) {
      final segment = segments[index];
      final child = node[segment];

      if (child == null) {
        return true;
      }

      if (_removeDep(child, segments, depSegments, index + 1)) {
        if (node.length == 1) {
          return true;
        }
        node.remove(segment);
      }

      return false;
    }

    final segment = segments[index];
    final Map? child = node[segment];
    if (child == null) {
      return true;
    }

    final Map? deps = child[_depKey];
    if (deps == null) {
      // If the child node exists but it has no dependencies, then it must just be a transient
      // node to another path with dependencies so it should not be deleted.
      return false;
    }

    if (_dec(deps, depSegments) && deps.length == 1) {
      // If the child node had no other keys than deps, then if the removed dependency was the last dependency,
      // delete the node.
      if (child.length == 1) {
        return true;
      } else {
        // Otherwise, just clear the child node's deps.
        child.remove(_depKey);
      }
    }

    if (index < segments.length - 1) {
      if (_removeDep(child, segments, depSegments, index + 1)) {
        if (child.length == 1) {
          return true;
        }
        child.remove(segments[index + 1]);
      }
    }

    return false;
  }

  void removeDep(String path, String depPath) {
    final pathSegments = path.split(_delimiter);
    final depSegments = depPath.split(_delimiter);

    if (_removeDep(_store, pathSegments, depSegments)) {
      _store.remove(pathSegments.first);
    }
  }

  Map inspect() {
    return _store;
  }
}
