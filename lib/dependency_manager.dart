part of loon;

class DependencyManager {
  /// The store of dependencies of documents indexed by document path.
  final _dependencies = ValueStore<Set<Document>>();

  /// The store of dependents of documents.
  final _dependents = <Document, Set<Document>?>{};

  /// The cache of documents referenced as dependencies. A cache is used so that multiple documents
  /// that share a dependency reference the same document instance.
  final _cache = <Document>{};

  /// Updates the dependencies/dependents store for the given [DocumentSnapshot]
  /// with the document's recalculated dependencies.
  void updateDependencies<T>(DocumentSnapshot<T> snap) {
    final doc = snap.doc;
    final deps = doc.dependenciesBuilder?.call(snap)?.map((dep) {
      // Maps the given dependenc to its cached dependency document, creating it if it does not exist yet.
      final cacheDoc = _cache.lookup(dep);
      if (cacheDoc == null) {
        _cache.add(dep);
      }
      return cacheDoc ?? dep;
    }).toSet();
    final prevDeps = _dependencies.get(doc.path);

    if (setEquals(deps, prevDeps)) {
      return;
    }

    if (deps != null && prevDeps != null) {
      final addedDeps = deps.difference(prevDeps);
      final removedDeps = prevDeps.difference(deps);

      for (final dep in addedDeps) {
        (_dependents[dep] ??= {}).add(doc);
      }
      for (final dep in removedDeps) {
        if (_dependents[dep]!.length == 1) {
          _dependents.remove(dep);
          _cache.remove(dep);
        } else {
          _dependents[dep]!.remove(doc);
        }
      }

      if (deps.isEmpty) {
        _dependencies.delete(doc.path);
      } else {
        _dependencies.write(doc.path, deps);
      }
    } else if (deps != null) {
      for (final dep in deps) {
        (_dependents[dep] ??= {}).add(doc);
      }

      _dependencies.write(doc.path, deps);
    } else if (prevDeps != null) {
      for (final dep in prevDeps) {
        if (_dependents[dep]!.length == 1) {
          _dependents.remove(dep);
        } else {
          _dependents[dep]!.remove(doc);
        }
      }

      _dependencies.delete(doc.path);
    }
  }

  Set<Document>? getDependencies(Document doc) {
    return _dependencies.get(doc.path);
  }

  Set<Document>? getDependents(Document doc) {
    final dependents = _dependents[doc];

    if (dependents == null) {
      return null;
    }

    for (final dep in dependents.toList()) {
      // If a dependent no longer exists in the store, then it is lazily removed from
      // the broadcast document's dependents.
      //
      // This scenario can occur if an entire subtree of documents was removed, in which case
      // the descendant documents did not eagerly remove themselves from their dependencies'
      // set of dependents, and instead they are removed lazily when the document accesses
      // its dependents.
      if (!dep.exists()) {
        dependents.remove(dep);
      }
    }

    if (dependents.isEmpty) {
      _dependents.remove(doc);
    }

    return dependents;
  }

  void deleteCollection(Collection collection) {
    _dependencies.delete(collection.path);
  }

  /// Clears all dependencies and dependents of documents.
  void clear() {
    _dependencies.clear();
    _dependents.clear();
  }

  Map inspect() {
    return {
      "dependencyStore": _dependencies.inspect(),
      "dependentsStore": _dependents,
      "documentCache": _cache,
    };
  }
}
