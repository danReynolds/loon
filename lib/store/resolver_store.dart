class ResolverStore {
  static const _delimiter = '__';
  static const _refs = '__refs';

  final Map _store = {};

  void _write(Map node, List<String> segments, int index, String value) {
    // Only every collection node stores data store ref data, it is unnecessary
    // for document nodes.
    final isRefNode = index % 2 == 0;
    final segment = segments[index];

    if (isRefNode) {
      final child = node[segment] ??= {};
      child[_refs] ??= <String, int>{};
      child[_refs][value] ??= 0;
      child[_refs][value]++;
    }

    if (index < segments.length - 1) {
      return _write(node[segment] ??= {}, segments, index + 1, value);
    }
  }

  void write(String path, String value) {
    _write(_store, path.split(_delimiter), 0, value);
  }

  Map<String, int>? _get(Map? node, List<String> segments, int index) {
    if (node == null) {
      return null;
    }

    if (index < segments.length) {
      return _get(node[segments[index]], segments, index + 1);
    }

    return node[_refs];
  }

  Map<String, int>? get(String path) {
    return _get(_store, path.split(_delimiter), 0);
  }

  Map<String, int>? _delete(Map? node, List<String> segments, int index) {
    if (node == null) {
      return null;
    }

    if (index < segments.length - 1) {
      final segment = segments[index];
      final Map? child = node[segment];

      final Map<String, int>? deletedRefs = _delete(child, segments, index + 1);

      if (deletedRefs == null) {
        return null;
      }

      // If the child node is empty after processing the delete, then remove it.
      if (child != null && child.isEmpty) {
        node.remove(segment);
      }

      // If this is a parent collection node with refs, then after receiving the deletion
      // ref counts, subtract this node's own ref counts by those deletion counts.
      if (node.containsKey(_refs)) {
        for (final entry in deletedRefs.entries) {
          final key = entry.key;
          final refCount = entry.value;
          final refs = node[_refs];

          // If any of this node's own ref counts are now zero, those keys can be removed.
          if (refs[key] - refCount == 0) {
            refs.remove(key);
          } else {
            refs[key] -= refCount;
          }

          if (refs.isEmpty) {
            node.remove(_refs);
          }
        }
      }

      return deletedRefs;
    }

    final segment = segments[index];
    if (!node.containsKey(segment)) {
      return null;
    }

    final Map child = node.remove(segments[index]);

    // If the final node in the path is a collection node with refs, then pass up
    // its old ref counts that each of its parent ref nodes in the path will decrement by.
    if (child.containsKey(_refs)) {
      node.remove(segment);
      return child[_refs];
    }

    // Otherwise, the final node in the path is a document node with no refs itself, but potentially
    // collection node children with refs. Aggregate their ref counts and pass them up to be decremented
    // by each of the parent collection ref nodes in the path.
    if (child.isNotEmpty) {
      final Map<String, int> deletedRefs = {};
      for (final value in child.values) {
        final Map<String, int> refs = value[_refs];
        for (final refEntry in refs.entries) {
          final key = refEntry.key;
          deletedRefs[key] ??= 0;
          deletedRefs[key] = deletedRefs[key]! + refEntry.value;
        }
      }

      for (final entry in deletedRefs.entries) {
        final key = entry.key;
        final refCount = entry.value;
        final refs = node[_refs];

        // If any of this node's own ref counts are now zero, those keys can be removed.
        if (refs[key] - refCount == 0) {
          refs.remove(key);
        } else {
          refs[key] -= refCount;
        }

        if (refs.isEmpty) {
          node.remove(_refs);
        }
      }

      return deletedRefs;
    }

    return null;
  }

  void delete(String path) {
    _delete(_store, path.split(_delimiter), 0);
  }

  Map inspect() {
    return _store;
  }
}
