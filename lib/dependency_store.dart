part of loon;

class DependencyStore {
  /// The store of documents that a document depends on.
  final _store = StoreNode<Set<Document>>();

  /// Rebuilds the set of dependencies of the given document based on its updated
  /// snapshot.
  void rebuild(Document doc) {
    final dependenciesBuilder = doc.dependenciesBuilder;

    if (dependenciesBuilder != null) {
      final path = doc.path;
      final deps = doc.dependenciesBuilder?.call(doc.get()!);

      if (deps != null) {
        _store.write(path, deps);
      } else if (_store.contains(path)) {
        _store.delete(path);
      }
    }
  }

  void delete(String path) {
    _store.delete(path);
  }

  void clear() {
    _store.clear();
  }

  Map inspect() {
    return _store.inspect();
  }
}
