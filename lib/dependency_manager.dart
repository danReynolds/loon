part of loon;

class DependencyManager {
  /// Global store of document dependencies.
  final Map<Document, Set<Document>> _dependenciesStore = {};
  final Map<Document, Set<Document>> _dependentsStore = {};

  /// On write of a snapshot, the dependencies manager updates the dependencies
  /// store with the updated document dependencies and
  void onWrite(DocumentSnapshot snap) {
    final doc = snap.doc;
    final deps = snap.doc.dependenciesBuilder?.call(snap);

    if (deps != null) {
      _dependenciesStore[doc] = deps;
    } else if (_dependenciesStore.containsKey(doc)) {
      _dependenciesStore.remove(doc);
    }
  }
}
