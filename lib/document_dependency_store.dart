part of loon;

/// The document dependency store maintains the dependency/dependent relationship of documents recalculated whenever a document changes (added, updated removed).
/// using the collection's [Collection.dependenciesBuilder] (if present). Whenever a document changes two things occur:
///
/// 1. The document's dependencies are recalculated, marking new dependencies in the dependency store and removing stale ones.
/// 2. If the document is marked for broadcast, then its dependents are also rebroadcast.
class _DocumentDependencyStore {
  /// The index of a document to the documents that depend on it. Whenever a document is updated, it schedules
  /// each of its dependents for a broadcast so that they can receive its updated value.
  final Map<Document, Set<Document>> _dependentsStore = {};

  /// The index of a document to the documents that it depends on. Whenever a document is updated, it records
  /// the updated set of documents that it now depends on.
  final Map<Document, Set<Document>> _dependenciesStore = {};

  /// Returns the set of dependencies (if any) that the given document is dependent on.
  Set<Document>? getDependencies(Document doc) {
    return _dependenciesStore[doc];
  }

  /// Returns the set of documents (if any) that are dependent on the given document.
  Set<Document>? getDependents(Document doc) {
    return _dependentsStore[doc];
  }

  /// Marks the given document as dependent on the given dependency.
  /// This involves adding an entry to both the dependencies and dependents collections:
  /// 1. The dependency should be added to the dependencies store for the given document.
  /// 2. The document should be added to the dependents store for the given dependency.
  void addDependency(Document doc, Document dependency) {
    if (!_dependentsStore.containsKey(dependency)) {
      _dependentsStore[dependency] = {};
    }

    if (!_dependenciesStore.containsKey(doc)) {
      _dependenciesStore[doc] = {};
    }

    _dependenciesStore[doc]!.add(dependency);
    _dependentsStore[dependency]!.add(doc);
  }

  /// Removes the given dependency from the given document.
  /// This involves removing an entry from both the dependencies and dependents collections:
  /// 1. The dependency should be removed from the dependencies store for the given document.
  /// 2. The document should be removed from the dependents store for the given dependency.
  void removeDependency(Document doc, Document dependency) {
    _dependenciesStore[doc]?.remove(dependency);
    _dependentsStore[dependency]?.remove(doc);
  }

  /// Clears all dependencies of the given document.
  /// This involves removing entries from both the dependencies and dependents collections:
  /// 1. All dependencies should be removed from the dependencies store for the given document.
  /// 2. The document should be removed from the dependents store of all of its dependencies.
  void clearDependencies(Document doc) {
    final dependencies = getDependencies(doc);

    if (dependencies == null) {
      return;
    }

    for (final dependency in dependencies.toList()) {
      removeDependency(doc, dependency);
    }
  }

  /// Rebuilds a document's set of dependencies (if any), storing updates in two different collections:
  /// 1. A mapping of a document to its dependencies (necessary for efficient calculation prev/next dependencies in rebuild)
  /// 2. A mapping of a document to the documents that depend on it (used to trigger rebroadcasts of dependent documents)
  void rebuildDependencies<T>(DocumentSnapshot<T> snap) {
    final doc = snap.doc;
    final dependenciesBuilder = doc.dependenciesBuilder;

    if (dependenciesBuilder == null) {
      return;
    }

    final prevDependencies = getDependencies(doc);
    final updatedDependencies = dependenciesBuilder(snap);

    // Remove the document from the dependents index of any documents that it no longer depends on.
    if (prevDependencies != null) {
      if (updatedDependencies == null) {
        for (final prevDependency in prevDependencies) {
          removeDependency(doc, prevDependency);
        }
      } else {
        final staleDependencies =
            prevDependencies.difference(updatedDependencies);
        for (final staleDependency in staleDependencies) {
          removeDependency(doc, staleDependency);
        }
      }
    }

    if (updatedDependencies != null) {
      for (final dependency in updatedDependencies) {
        addDependency(doc, dependency);
      }
    }
  }

  void clear() {
    _dependenciesStore.clear();
    _dependentsStore.clear();
  }
}
