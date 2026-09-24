part of 'loon.dart';

/// Keeps the dependent handle available when its dependency entries are deleted.
class _DependencyEntry {
  final Document doc;
  final Set<Document> dependencies;

  _DependencyEntry(this.doc, this.dependencies);

  Json toJson() => {
        'doc': doc.path,
        'dependencies': [
          for (final dependency in dependencies) dependency.path
        ],
      };
}

class DependencyManager {
  /// The index of dependencies of a document by path. Documents without dependencies have no entry.
  final _dependencies = ValueStore<_DependencyEntry>();

  /// The reverse index of dependents of a document by path.
  final _dependents = ValueStore<Set<Document>>();

  void _addDependent(Document dependency, Document dependent) {
    final dependents = _dependents.get(dependency.path) ??
        _dependents.write(dependency.path, {});
    dependents.add(dependent);
  }

  void _removeDependent(Document dependency, Document dependent) {
    final dependents = _dependents.get(dependency.path);
    if (dependents == null) return;

    dependents.remove(dependent);
    if (dependents.isEmpty) {
      _dependents.delete(dependency.path, recursive: false);
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

    final deps = dependenciesBuilder.call(snap);
    final prevDeps = _dependencies.get(doc.path)?.dependencies;

    if (setEquals(deps, prevDeps)) {
      return;
    }

    if (deps != null) {
      for (final dep in deps) {
        if (prevDeps?.contains(dep) != true) {
          _addDependent(dep, doc);
        }
      }
    }
    if (prevDeps != null) {
      for (final dep in prevDeps) {
        if (deps?.contains(dep) != true) {
          _removeDependent(dep, doc);
        }
      }
    }

    if (deps != null && deps.isNotEmpty) {
      // Keep the stored dependencies independent of a mutable set owned by the builder.
      _dependencies.write(doc.path, _DependencyEntry(doc, deps.toSet()));
    } else if (prevDeps != null) {
      // Remove the entry of a document whose dependencies were cleared. Subcollections keep
      // their own dependency entries.
      _dependencies.delete(doc.path, recursive: false);
    }
  }

  /// Returns all dependencies of the given document.
  Set<Document>? getDependencies(Document doc) {
    return _dependencies.get(doc.path)?.dependencies;
  }

  /// Returns all dependents under the given store reference.
  Set<Document>? getDependents(
    StoreReference ref, {
    bool recursive = false,
  }) {
    if (!recursive) {
      return _dependents.get(ref.path);
    }

    final dependents = <Document>{};
    _dependents.forEachValue(ref.path, dependents.addAll);
    return dependents;
  }

  /// Deleting a store ref performs two operations:
  ///
  /// 1. It removes the documents under the given path from their dependencies' reverse indexes,
  ///    reading their dependency entries.
  /// 2. It deletes those entries, which must come second since the first step reads them.
  ///
  /// Surviving documents that depend on the deleted path keep their memberships,
  /// so they can react to both its deletion and later recreation.
  void _deleteRef(StoreReference ref) {
    final StoreReference(:path) = ref;

    _dependencies.forEachValue(path, (entry) {
      for (final dependency in entry.dependencies) {
        _removeDependent(dependency, entry.doc);
      }
    });

    _dependencies.delete(path);
  }

  void deleteDocument(Document doc) {
    _deleteRef(doc);
  }

  void deleteCollection(Collection collection) {
    _deleteRef(collection);
  }

  /// Clears all dependencies and dependents of documents.
  void clear() {
    _dependencies.clear();
    _dependents.clear();
  }

  Map inspect() {
    return {
      "dependencyStore": _dependencies.inspect(),
      "dependentsStore": _dependents.inspect(),
    };
  }
}
