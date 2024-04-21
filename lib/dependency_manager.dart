part of loon;

class DependencyManager {
  /// Global store of document dependencies.
  final _dependenciesStore = DepStore();
  final Map<Document, Set<Document>> _dependentsStore = {};

  /// On write of a snapshot, the dependencies manager updates the dependencies
  /// store with the updated document dependencies and
  void onWrite(DocumentSnapshot snap) {
    final doc = snap.doc;
    final deps = snap.doc.dependenciesBuilder?.call(snap);

    if (deps != null) {
      for (final dep in deps) {
        _dependenciesStore.addDep(doc.path, dep.path);
      }
    }
  }
}
