part of 'loon.dart';

class DependencyManager {
  /// The store of dependencies of documents indexed by document path.
  final _dependencies = ValueStore<Set<Document>>();

  /// The store of dependents of documents indexed by the path of the document they depend on.
  /// Each document's dependents are themselves indexed by path, so that when a path is deleted
  /// the dependents under it (which are deleted along with it) can be dropped with a single
  /// delete, and the dependents of every document under the path can be found together.
  final _dependents = ValueStore<ValueStore<Document>>();

  /// The cache of documents referenced as dependencies. A cache is used so that multiple documents
  /// that share the same dependency reference the same object.
  final _depCache = <Document>{};

  void _addDependent(Document dep, Document doc) {
    final dependents = _dependents.get(dep.path) ??
        _dependents.write(dep.path, ValueStore<Document>());
    dependents.write(doc.path, doc);
  }

  void _removeDependent(Document dep, Document doc) {
    final dependents = _dependents.get(dep.path);
    if (dependents == null) {
      return;
    }

    // Only the document's own membership is removed; the documents of its subcollections keep
    // theirs.
    dependents.delete(doc.path, recursive: false);
    _pruneDependency(dep, dependents);
  }

  /// Removes the dependency's entry once it has no dependents left.
  void _pruneDependency(Document dep, ValueStore<Document> dependents) {
    if (dependents.isEmpty) {
      _dependents.delete(dep.path, recursive: false);
      _depCache.remove(dep);
    }
  }

  /// Updates the dependencies/dependents store for the given [DocumentSnapshot]
  /// with the document's recalculated dependencies.
  void updateDependencies<T>(DocumentSnapshot<T> snap) {
    final doc = snap.doc;
    final dependenciesBuilder = doc.dependenciesBuilder;

    if (dependenciesBuilder == null) {
      return;
    }

    final deps = dependenciesBuilder.call(snap)?.map((dep) {
      final cacheDoc = _depCache.lookup(dep);
      if (cacheDoc == null) {
        _depCache.add(dep);
      }
      return cacheDoc ?? dep;
    }).toSet();
    final prevDeps = _dependencies.get(doc.path);

    if (setEquals(deps, prevDeps)) {
      return;
    }

    if (deps != null && prevDeps != null) {
      for (final dep in deps.difference(prevDeps)) {
        _addDependent(dep, doc);
      }
      for (final dep in prevDeps.difference(deps)) {
        _removeDependent(dep, doc);
      }

      if (deps.isEmpty) {
        // Only the document's own dependencies are removed; the documents of its
        // subcollections keep theirs.
        _dependencies.delete(doc.path, recursive: false);
      } else {
        _dependencies.write(doc.path, deps);
      }
    } else if (deps != null) {
      for (final dep in deps) {
        _addDependent(dep, doc);
      }

      _dependencies.write(doc.path, deps);
    } else if (prevDeps != null) {
      for (final dep in prevDeps) {
        _removeDependent(dep, doc);
      }

      _dependencies.delete(doc.path, recursive: false);
    }
  }

  Set<Document>? getDependencies(Document doc) {
    return _dependencies.get(doc.path);
  }

  /// Returns the existing dependents of the given document.
  Set<Document>? getDependents(Document doc) {
    final dependents = _dependents.get(doc.path);

    if (dependents == null) {
      return null;
    }

    final result = <Document>{};
    for (final dep in dependents.extractValues()) {
      // If a dependent no longer exists in the store, then it is lazily removed from
      // the document's dependents.
      //
      // This scenario can occur if an entire subtree of documents was removed, in which case
      // the descendant documents did not eagerly remove themselves from their dependencies'
      // set of dependents, and instead they are removed lazily when the document accesses
      // its dependents.
      if (dep.exists()) {
        result.add(dep);
      } else {
        dependents.delete(dep.path, recursive: false);
      }
    }
    _pruneDependency(doc, dependents);

    return result;
  }

  /// Returns the existing dependents of the document or collection at the given path and of every
  /// document under it (such as the documents of a deleted document's subcollections). Dependents
  /// that are themselves under the path are deleted along with it, so they are dropped from the
  /// index rather than returned.
  Set<Document> getPathDependents(String path) {
    final result = <Document>{};

    for (final entry in _dependents.extract(path).entries) {
      final dependents = entry.value;

      dependents.delete(path);

      for (final dep in dependents.extractValues()) {
        if (dep.exists()) {
          result.add(dep);
        } else {
          dependents.delete(dep.path, recursive: false);
        }
      }
      _pruneDependency(Document.fromPath(entry.key), dependents);
    }

    return result;
  }

  void deleteDocument(Document doc) {
    _dependencies.delete(doc.path);
  }

  void deleteCollection(Collection collection) {
    _dependencies.delete(collection.path);
  }

  /// Clears all dependencies and dependents of documents.
  void clear() {
    _dependencies.clear();
    _dependents.clear();
    _depCache.clear();
  }

  Map inspect() {
    return {
      "dependencyStore": _dependencies.inspect(),
      "dependentsStore": {
        for (final entry in _dependents.extract().entries)
          entry.key: entry.value.inspect(),
      },
      "dependencyCache": _depCache,
    };
  }
}
